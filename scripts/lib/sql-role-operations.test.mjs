import test from 'node:test'
import assert from 'node:assert/strict'
import {
  canonicalRoleName,
  validateRoleClaimTarget,
  normalizeRoleClaim,
  extractRoleOperations,
  roleCollisionKeys,
  roleOwnershipDependencies,
  findDynamicRoleMutations,
  assertNoDynamicRoleMutations,
  RoleExtractionError,
  RoleClaimError,
} from './sql-role-operations.mjs'

// ---------------------------------------------------------------------------
// Exact global role identity — quoted case preserved, unquoted folded,
// schema-qualified refused. Roles are cluster-global: one name, no schema.
// ---------------------------------------------------------------------------
test('exact global role identity preserves quoted case and folds unquoted', () => {
  assert.equal(canonicalRoleName('pm_jev_triage_worker'), 'pm_jev_triage_worker')
  assert.equal(canonicalRoleName('MyRole'), 'myrole') // unquoted folds to lowercase
  assert.equal(canonicalRoleName('myrole'), 'myrole')
  assert.equal(canonicalRoleName('"myrole"'), 'myrole') // quoted-lowercase == unquoted
  assert.equal(canonicalRoleName('"MyRole"'), '"MyRole"') // quoted case preserved
  assert.equal(canonicalRoleName('"PM_JEV_TRIAGE_WORKER"'), '"PM_JEV_TRIAGE_WORKER"')
  assert.equal(canonicalRoleName('"a""b"'), '"a""b"') // internal quote unescaped, then re-quoted
})

test('a broad schema claim is not a reservation on a global role', () => {
  // Schema-qualified names are not single global roles.
  assert.equal(canonicalRoleName('public.pm_jev_triage_worker'), null)
  assert.equal(canonicalRoleName('schema.role'), null)
  assert.equal(canonicalRoleName(''), null)
  assert.equal(canonicalRoleName('   '), null)
  assert.equal(canonicalRoleName('1bad'), null)
  // The role key namespace is distinct from the schema key namespace.
  assert.deepEqual(roleCollisionKeys('create role public'), ['role public'])
  assert.notDeepEqual(roleCollisionKeys('create role public'), ['schema public'])
})

// ---------------------------------------------------------------------------
// Claim support: `role <name>` is a valid exact global claim.
// ---------------------------------------------------------------------------
test('role claims normalize to exact global identity and reject bad forms', () => {
  assert.equal(normalizeRoleClaim('role pm_jev_triage_worker'), 'role pm_jev_triage_worker')
  assert.equal(normalizeRoleClaim('  role   MyRole '), 'role myrole')
  assert.equal(normalizeRoleClaim('role "MyRole"'), 'role "MyRole"')
  assert.equal(validateRoleClaimTarget('pm_jev_triage_worker'), 'pm_jev_triage_worker')
  assert.throws(() => normalizeRoleClaim('role public.worker'), RoleClaimError) // schema-qualified
  assert.throws(() => normalizeRoleClaim('role'), RoleClaimError) // no target
  assert.throws(() => normalizeRoleClaim('table core.x'), RoleClaimError) // wrong kind
  assert.throws(() => validateRoleClaimTarget('a.b'), RoleClaimError)
})

// ---------------------------------------------------------------------------
// CREATE / ALTER / DROP ROLE extraction.
// ---------------------------------------------------------------------------
test('create, alter and drop role are each accounted on the exact role', () => {
  const ops = extractRoleOperations(`
    create role worker nologin;
    alter role worker nologin;
    drop role worker;
  `).operations
  const actions = ops.map((o) => `${o.action}:${o.target}`).sort()
  assert.deepEqual(actions, ['alter:worker', 'create:worker', 'drop:worker'])
  assert.deepEqual(roleCollisionKeys('create role worker nologin;'), ['role worker'])
})

test('drop role lists emit one operation per name', () => {
  const ops = extractRoleOperations('drop role if exists a, b, "C";').operations
  assert.deepEqual(ops.map((o) => o.target).sort(), ['"C"', 'a', 'b'])
})

test('USER and GROUP spellings are the same role command and are not skipped', () => {
  assert.deepEqual(roleCollisionKeys('create user worker;'), ['role worker'])
  assert.deepEqual(roleCollisionKeys('alter group worker nologin;'), ['role worker'])
  assert.deepEqual(roleCollisionKeys('drop user worker;'), ['role worker'])
})

// ---------------------------------------------------------------------------
// Rename: BOTH identities reserved, but never aliased into one.
// ---------------------------------------------------------------------------
test('rename reserves both old and new identities and keeps them independent', () => {
  const ops = extractRoleOperations('alter role old_name rename to new_name;').operations
  assert.equal(ops.length, 1)
  assert.deepEqual({ action: ops[0].action, from: ops[0].from, to: ops[0].to }, { action: 'rename', from: 'old_name', to: 'new_name' })
  // Both are reserved (would collide with any other write to either)…
  assert.deepEqual(roleCollisionKeys('alter role old_name rename to new_name;'), ['role new_name', 'role old_name'])
  // …but they remain two DISTINCT identities (no alias collapse): only the new
  // name overlaps with a separate `create role new_name`, never the old name.
  const c1 = roleCollisionKeys('alter role old_name rename to new_name;')
  const c2 = roleCollisionKeys('create role new_name;')
  assert.deepEqual(c1.filter((k) => c2.includes(k)), ['role new_name'])
  assert.deepEqual(roleCollisionKeys('create role old_name;').filter((k) => c2.includes(k)), [])
})

// ---------------------------------------------------------------------------
// Membership GRANT/REVOKE — connects distinct roles, never merges them.
// ---------------------------------------------------------------------------
test('membership grant/revoke account every named role and keep them distinct', () => {
  const g = extractRoleOperations('grant worker to app_group;').operations
  assert.equal(g.length, 1)
  assert.equal(g[0].action, 'grant_membership')
  assert.deepEqual(g[0].members, ['worker'])
  assert.deepEqual(g[0].grantees, ['app_group'])
  // Both roles reserved…
  assert.deepEqual(roleCollisionKeys('grant worker to app_group;'), ['role app_group', 'role worker'])
  // …yet independent: `grant a to b` and `create role a` collide on `role a` only.
  const mKeys = roleCollisionKeys('grant worker to app_group;')
  const aKeys = roleCollisionKeys('create role worker;')
  assert.deepEqual(mKeys.filter((k) => aKeys.includes(k)), ['role worker'])
  assert.deepEqual(roleCollisionKeys('revoke worker from app_group;').sort(), ['role app_group', 'role worker'])
})

test('multi-role membership lists account each role once', () => {
  const keys = roleCollisionKeys('grant r1, r2 to g1, g2;')
  assert.deepEqual(keys, ['role g1', 'role g2', 'role r1', 'role r2'])
})

test('privilege grants are never mistaken for role membership', () => {
  // `on` before the connector ⇒ privilege grant, not membership.
  assert.deepEqual(roleCollisionKeys('grant select on table t to r;'), [])
  assert.deepEqual(roleCollisionKeys('grant all on schema s to r;'), [])
  assert.deepEqual(roleCollisionKeys('revoke insert on table t from r;'), [])
  assert.deepEqual(extractRoleOperations('grant select on table t to r;').operations, [])
})

test('special grantees and privilege keywords never become role names', () => {
  assert.deepEqual(roleCollisionKeys('grant select, insert to public;'), [])
  assert.deepEqual(roleCollisionKeys('revoke all from current_user;'), [])
})

// ---------------------------------------------------------------------------
// Same-role conflicts and distinct-role independence.
// ---------------------------------------------------------------------------
test('same role conflicts across spellings; distinct roles stay independent', () => {
  const sameA = roleCollisionKeys('create role a;')
  const sameB = roleCollisionKeys('alter role a nologin;')
  assert.deepEqual(sameA, ['role a'])
  assert.deepEqual(sameB, ['role a'])
  assert.deepEqual(sameA.filter((k) => sameB.includes(k)), ['role a']) // SAME role ⇒ conflict
  const distinct = roleCollisionKeys('create role a; create role b;')
  assert.deepEqual(distinct, ['role a', 'role b'])
  const other = roleCollisionKeys('create role c;')
  assert.deepEqual(distinct.filter((k) => other.includes(k)), []) // distinct ⇒ independent
})

// ---------------------------------------------------------------------------
// Ownership dependencies — recorded, but NEVER an exclusive write on the role.
// ---------------------------------------------------------------------------
test('function/table ownership is a dependency on the role, not a write to it', () => {
  const sql = 'alter function pim.worker() owner to pm_jev_triage_worker; alter table pim.triage owner to pm_jev_triage_worker;'
  const deps = roleOwnershipDependencies(sql)
  assert.equal(deps.length, 2)
  assert.deepEqual(deps.map((d) => `${d.ownerKind}:${d.role}`).sort(), ['function:pm_jev_triage_worker', 'table:pm_jev_triage_worker'])
  // CRITICAL: the role is NOT reserved as an exclusive write.
  assert.deepEqual(roleCollisionKeys(sql), [])
  // Two migrations that each own a different object to the same role do not
  // collide with each other on that role.
  const k1 = roleCollisionKeys('alter function a() owner to shared;')
  const k2 = roleCollisionKeys('alter table b owner to shared;')
  assert.deepEqual(k1.filter((x) => k2.includes(x)), [])
})

test('ownership dependency does not collide with a role write, but is still recorded', () => {
  // A drop of the role is a write; the dependency is not. A consumer can pair
  // them to detect "drop a role an object depends on" without the dependency
  // itself reserving the role.
  assert.deepEqual(roleCollisionKeys('drop role shared;'), ['role shared'])
  assert.deepEqual(roleCollisionKeys('alter table t owner to shared;'), [])
  assert.equal(roleOwnershipDependencies('alter table t owner to shared;')[0].role, 'shared')
})

test('owner to CURRENT_USER records no named role dependency', () => {
  assert.deepEqual(roleOwnershipDependencies('alter table t owner to current_user;'), [])
})

// ---------------------------------------------------------------------------
// Literal DO handling — role DDL inside a top-level DO block is migration-time.
// ---------------------------------------------------------------------------
test('literal role DDL inside a DO block is extracted', () => {
  const sql = `do $$
  begin
    create role designflow_hts_prod_worker nologin;
    alter role designflow_hts_prod_worker nologin;
  end $$;`
  const keys = roleCollisionKeys(sql)
  assert.deepEqual(keys, ['role designflow_hts_prod_worker'])
  const ops = extractRoleOperations(sql).operations.map((o) => o.action).sort()
  assert.deepEqual(ops, ['alter', 'create'])
})

// ---------------------------------------------------------------------------
// Dynamic role mutations are REFUSED (fail closed), never skipped.
// ---------------------------------------------------------------------------
test('dynamic role DDL hidden in an EXECUTE/format string fails closed', () => {
  const sql = `do $$
  begin
    execute format('create role %I', 'sneaky');
  end $$;`
  const found = findDynamicRoleMutations(sql)
  assert.equal(found.length, 1)
  assert.match(found[0].text, /create role/i)
  assert.throws(() => assertNoDynamicRoleMutations(sql), RoleExtractionError)
  assert.throws(() => roleCollisionKeys(sql), RoleExtractionError) // refuse, not "clear"
})

test('dynamic role DDL in a concatenated EXECUTE string fails closed', () => {
  const sql = `do $$ begin execute 'alter role ' || quote_ident(r) || ' nologin'; end $$;`
  assert.throws(() => roleCollisionKeys(sql), RoleExtractionError)
})

test('dynamic membership DDL in a string fails closed', () => {
  const sql = `do $$ begin execute 'grant worker to app_group'; end $$;`
  assert.throws(() => roleCollisionKeys(sql), RoleExtractionError)
})

test('prose that merely mentions grant/role is not a dynamic role mutation', () => {
  // Mid-sentence prose and privilege-shaped text must not trip the refusal.
  assert.deepEqual(findDynamicRoleMutations(`comment on table t is 'roles do not grant read on their own'`), [])
  assert.deepEqual(findDynamicRoleMutations(`do $$ begin raise notice 'create a role for auditing'; end $$;`), [])
  assert.deepEqual(findDynamicRoleMutations(`do $$ begin raise notice 'we create role x for audit later'; end $$;`), [])
  assert.deepEqual(findDynamicRoleMutations(`do $$ begin execute 'grant select on t to r'; end $$;`), []) // privilege, not membership
  // No dynamic mutation ⇒ the literal path is clean.
  assert.deepEqual(roleCollisionKeys(`comment on table t is 'we create role x for audit later'`), [])
})

test('a string holding an exact role DDL statement is refused as dynamic', () => {
  // A string whose content IS a role statement is indistinguishable from SQL
  // that would be EXECUTEd; fail closed rather than guess it is prose.
  assert.throws(() => roleCollisionKeys(`comment on table t is 'create role x'`), RoleExtractionError)
})

test('role DDL written literally inside a function body is deferred, not a migration axis', () => {
  // Consistent with the collision parser blanking function bodies: a role DDL in
  // a non-DO body runs at call time, not migration time.
  const sql = `create function f() returns void language plpgsql as $fn$ begin perform 1; end $fn$;`
  assert.deepEqual(findDynamicRoleMutations(sql), [])
  assert.deepEqual(roleCollisionKeys(sql), [])
})

// ---------------------------------------------------------------------------
// No synthetic evidence, no count caps.
// ---------------------------------------------------------------------------
test('empty / non-role SQL yields no operations and no fabricated keys', () => {
  assert.deepEqual(roleCollisionKeys('select 1;'), [])
  assert.deepEqual(extractRoleOperations('create table t();').operations, [])
  assert.deepEqual(roleOwnershipDependencies('create table t();'), [])
})

test('many distinct roles are all tracked with no cap', () => {
  const many = Array.from({ length: 50 }, (_, i) => `create role r${i};`).join(' ')
  const keys = roleCollisionKeys(many)
  assert.equal(keys.length, 50)
  assert.deepEqual(keys, Array.from({ length: 50 }, (_, i) => `role r${i}`).sort())
})

// ---------------------------------------------------------------------------
// Real-world shape: the four NOLOGIN roles from migration 20260911210709.
// ---------------------------------------------------------------------------
test('the four NOLOGIN least-privilege roles are each reserved distinctly', () => {
  const sql = `
    create role designflow_hts_prod_runtime   nologin noinherit nosuperuser;
    create role designflow_hts_alsand_runtime nologin noinherit nosuperuser;
    create role designflow_hts_prod_worker    nologin noinherit nosuperuser;
    create role designflow_hts_alsand_worker  nologin noinherit nosuperuser;
    grant usage on schema hts_rag to designflow_hts_prod_worker;
  `
  const keys = roleCollisionKeys(sql)
  assert.deepEqual(keys, [
    'role designflow_hts_alsand_runtime',
    'role designflow_hts_alsand_worker',
    'role designflow_hts_prod_runtime',
    'role designflow_hts_prod_worker',
  ])
  // A claim for ONE of them must be a valid exact global role…
  assert.equal(normalizeRoleClaim('role designflow_hts_prod_worker'), 'role designflow_hts_prod_worker')
  // …and a second migration touching the SAME role collides, while a distinct
  // role does not.
  const same = roleCollisionKeys('alter role designflow_hts_prod_worker nologin;')
  assert.deepEqual(same.filter((k) => keys.includes(k)), ['role designflow_hts_prod_worker'])
  const distinct = roleCollisionKeys('create role pm_jev_triage_worker;')
  assert.deepEqual(distinct.filter((k) => keys.includes(k)), [])
})
