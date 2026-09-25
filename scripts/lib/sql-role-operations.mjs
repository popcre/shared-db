//
// EXACT GLOBAL ROLE IDENTITY + SQL ROLE OPERATION ACCOUNTING (issue #3398).
//
// THE GAP THIS CLOSES. Structural issue #3298 needs to reserve a dedicated
// cluster-global NOLOGIN worker role (`role pm_jev_triage_worker`) in a db-claim.
// Today the claim validator rejects `role <name>` ("unknown object kind in
// claim: role …") and the SQL collision parser lists `create role`/`alter role`
// under DISPATCH_UNMODELLED_FORMS on the assumption that roles are
// Supabase-managed. That assumption is false: migration 20260911210709 creates
// four application-specific NOLOGIN roles. A broad `schema` claim is NOT a
// reservation on a cluster-global role, and two migrations touching the SAME
// role must collide while distinct roles stay independent.
//
// This module is the pure, offline accounting layer those two call sites will
// import once their active owners release them. It deliberately owns only the
// role axis:
//
//   * exact global role identity, preserving quoted-identifier case;
//   * CREATE / ALTER / DROP ROLE, rename targets, and membership GRANT/REVOKE;
//   * function/table ownership role DEPENDENCIES (recorded, never as an
//     exclusive write on the role);
//   * literal DO/dynamic-SQL rules reused from the collision parser, with
//     dynamic role mutations REFUSED (fail closed) rather than skipped.
//
// DESIGN INVARIANTS (the issue forbids weakening any of these):
//
//   (1) NO ALIASES. Every role name is its own exact identity. A rename yields
//       TWO independent identities (old and new are both reserved, but they are
//       never collapsed into one). Membership links two DISTINCT roles and
//       never merges them. There is no name-alias map anywhere here.
//   (2) NO COUNT CAPS. Roles are tracked in unbounded sets; nothing truncates.
//   (3) NO WEAKER CHECKS / SYNTHETIC EVIDENCE. Every operation is read out of
//       real SQL text. Nothing is invented, guessed, or defaulted to "clear".
//   (4) FAIL CLOSED on dynamic role mutations. Role DDL hidden inside a dynamic
//       SQL string (`EXECUTE format('CREATE ROLE %I', …)`) is invisible to the
//       literal extractor. Rather than report a false "touches no role", the
//       extractor surfaces it as a refusal the caller must honour — the same
//       fail-closed posture as the immutable-sidecar evidence rules.
//
// Pure and offline: no GitHub, no database, no secrets.

export class RoleExtractionError extends Error {}
export class RoleClaimError extends Error {}

// A role is a SINGLE cluster-global identifier — never schema-qualified. This
// matches PostgreSQL: `CREATE ROLE schema.name` is invalid, but a quoted role
// may legally contain a dot (`CREATE ROLE "my.role"` names one role).
const IDENT = String.raw`(?:"(?:[^"]|"")*"|[A-Za-z_][A-Za-z0-9_$]*)`
// Schema-qualified object name (for ownership dependencies, which ARE qualified).
const QUALIFIED = String.raw`(?:${IDENT}\s*\.\s*)?${IDENT}`

// Words that may appear in a GRANT/REVOKE role list but are NOT role names.
// Filtering these is what keeps membership separate from privilege grants
// (`grant select on t to r`) and from `PUBLIC`/`CURRENT_USER` grantees.
const NON_ROLE_KEYWORDS = new Set([
  // privilege names (so a privilege list never reads as a membership list)
  'select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger',
  'usage', 'create', 'connect', 'temp', 'temporary', 'execute', 'all',
  'alter', 'set', 'reset', 'role', 'user', 'group',
  // special grantees / role references
  'public', 'current_user', 'current_role', 'session_user', 'user',
  'current_catalog', 'current_schema',
])

/**
 * Canonical identity for one cluster-global role name.
 *
 * Returns the collision-safe identity string, or null when `raw` is not a single
 * exact role identifier (e.g. schema-qualified, empty, or garbage).
 *
 * Quoted-case rule (matches the repo's `canonicalIdentifierParts` convention):
 * PostgreSQL folds an UNQUOTED identifier to lowercase, so `MyRole` names
 * `myrole`. A QUOTED name keeps its exact case: `"MyRole"` is the role
 * `MyRole`, distinct from `myrole`. A quoted name that is already a legal
 * lowercase unquoted identifier (`"foo"`) names the same role as `foo` and
 * folds to it. Non-lowercase quoted names are re-quoted in the identity so
 * `"MyRole"` and `myrole` can never share a key.
 */
export function canonicalRoleName(raw) {
  if (raw === null || raw === undefined) return null
  const text = String(raw).trim()
  const m = /^(?:"((?:[^"]|"")*)"|([A-Za-z_][A-Za-z0-9_$]*))$/.exec(text)
  if (!m) return null
  if (m[1] !== undefined) {
    const value = m[1].replace(/""/g, '"')
    return /^[a-z_][a-z0-9_$]*$/.test(value) ? value : `"${value.replace(/"/g, '""')}"`
  }
  return m[2].toLowerCase()
}

function canonicalRoleOrThrow(raw) {
  const name = canonicalRoleName(raw)
  if (!name) throw new RoleClaimError(`role claim must name one exact global role: ${raw}`)
  return name
}

/**
 * Validate the TARGET half of a `role <target>` claim and return its canonical
 * global identity. Rejects schema-qualified or non-identifier targets.
 */
export function validateRoleClaimTarget(target) {
  return canonicalRoleOrThrow(target)
}

/**
 * Normalize a full `role <target>` claim object to `role <canonical>`.
 * This is the hook the claim validator will call to accept exact global roles.
 */
export function normalizeRoleClaim(object) {
  const compact = String(object).trim().replace(/\s+/g, ' ')
  const m = /^role\s+(.+)$/i.exec(compact)
  if (!m) throw new RoleClaimError(`not a role claim: ${object}`)
  return `role ${canonicalRoleOrThrow(m[1])}`
}

/**
 * `ALTER … OWNER TO <role>` and `CREATE SCHEMA … AUTHORIZATION <role>` create a
 * DEPENDENCY from an object onto a role. This is intentionally NOT a write on
 * the role: two migrations that each hand ownership of different functions to
 * the same role must NOT collide with each other. The dependency is returned so
 * a consumer can still detect a role DROP that would break a dependent object.
 */
function pushOwnership(deps, kind, nameRaw, ownerRaw) {
  const role = canonicalRoleName(ownerRaw)
  if (!role) return
  // CURRENT_USER / SESSION_USER / CURRENT_ROLE / USER name no fixed role, so
  // they create no role dependency to track.
  const bare = role.replace(/^"|"$/g, '').toLowerCase()
  if (NON_ROLE_KEYWORDS.has(bare) || bare === 'current_user' || bare === 'current_role' || bare === 'session_user') return
  deps.push({ action: 'owner_dependency', role, ownerKind: kind, ownerTarget: nameRaw })
}

// ---------------------------------------------------------------------------
// Literal / DO-block extraction. Reuses the collision parser's established
// rules verbatim: strip comments + collapse whitespace; keep the body of a
// top-level `DO $$ … $$` (this repo's normal idempotent migration form) while
// blanking other dollar-quoted bodies and single-quoted string literals.
// ---------------------------------------------------------------------------

/** PostgreSQL accepts `DO $$…$$` and `DO LANGUAGE plpgsql $tag$…$tag$`. */
function dollarQuoteStartsDo(source, offset) {
  return /\bdo(?:\s+language\s+[a-z_][a-z0-9_$]*)?\s*$/i.test(source.slice(0, offset))
}

function normalizeSql(sql) {
  return stripSqlComments(String(sql).replace(/\r\n?/g, '\n')).replace(/\s+/g, ' ')
}

function stripSqlComments(sql) {
  let out = ''
  let i = 0
  let dollarTag = null
  while (i < sql.length) {
    const ch = sql[i]
    if (ch === '-' && sql[i + 1] === '-') {
      const nl = sql.indexOf('\n', i)
      i = nl === -1 ? sql.length : nl
      continue
    }
    if (ch === '/' && sql[i + 1] === '*') {
      const end = sql.indexOf('*/', i + 2)
      out += ' '
      i = end === -1 ? sql.length : end + 2
      continue
    }
    if (ch === '$') {
      const m = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(sql.slice(i, i + 64))
      if (m && (dollarTag === null || m[0] === dollarTag)) {
        dollarTag = dollarTag === null ? m[0] : null
        out += m[0]
        i += m[0].length
        continue
      }
    }
    if (ch === "'" && dollarTag === null) {
      let j = i + 1
      while (j < sql.length) {
        if (sql[j] === "'") {
          if (sql[j + 1] === "'") { j += 2; continue }
          break
        }
        j++
      }
      out += sql.slice(i, j + 1)
      i = j + 1
      continue
    }
    out += ch
    i++
  }
  return out
}

/**
 * Split normalized SQL into the extractable stream plus the regions the literal
 * extractor cannot see (single-quoted strings and non-DO dollar bodies). The
 * hidden regions are exactly where a DYNAMIC role mutation can hide.
 */
function extractableAndHidden(sql) {
  const hidden = []
  const base = normalizeSql(sql)
  const afterDollar = base.replace(/\$([A-Za-z_]*)\$([\s\S]*?)\$\1\$/g, (whole, _tag, body, offset, source) => {
    if (dollarQuoteStartsDo(source, offset)) return body
    hidden.push({ kind: 'dollar-body', text: body })
    return ' '
  })
  const extractable = afterDollar.replace(/'(?:[^']|'')*'/g, (whole) => {
    hidden.push({ kind: 'string-literal', text: whole.slice(1, -1).replace(/''/g, "'") })
    return " '' "
  })
  return { extractable, hidden }
}

function splitRoleList(raw) {
  const parts = []
  let start = 0
  let quoted = false
  for (let i = 0; i < raw.length; i += 1) {
    const c = raw[i]
    if (c === '"') {
      if (quoted && raw[i + 1] === '"') { i += 1; continue }
      quoted = !quoted
    } else if (!quoted && c === ',') {
      parts.push(raw.slice(start, i))
      start = i + 1
    }
  }
  parts.push(raw.slice(start))
  return parts.map((p) => p.trim()).filter(Boolean)
}

function roleNamesFrom(listRaw) {
  return splitRoleList(listRaw)
    .map((p) => canonicalRoleName(p))
    .filter((name) => {
      if (!name) return false
      const bare = name.replace(/^"|"$/g, '').toLowerCase()
      return !NON_ROLE_KEYWORDS.has(bare)
    })
}

// Statement-boundary-anchored role DDL, for detecting a role mutation hidden in
// a dynamic SQL string. Anchoring (start / after `;` / `begin` / `then`) is what
// keeps mid-sentence prose ("… do not grant read on their own …") from reading
// as executable membership DDL.
function looksLikeRoleStatement(content) {
  return content.split(';').some((seg) => {
    const s = seg.trim()
    if (!s) return false
    if (/^(?:create|alter|drop)\s+(?:role|user|group)\b/i.test(s)) return true
    const mem = /^(?:grant|revoke)\s+(?:admin\s+option\s+for\s+)?([\s\S]*?)\s+(?:to|from)\s+([\s\S]*)$/i.exec(s)
    if (!mem) return false
    // A privilege grant carries `on <object>` before the connector; membership does not.
    return !/\bon\b/i.test(mem[1])
  })
}

/**
 * Role DDL hidden inside dynamic SQL strings. These are invisible to the literal
 * extractor (the string is blanked), so they are REFUSED rather than skipped.
 *
 * Only single-quoted string literals are scanned: a role verb inside a string is
 * dynamic SQL (`EXECUTE '…'`, `EXECUTE format('CREATE ROLE %I', …)`). Role DDL
 * written literally inside a non-DO function body is deferred to call time and
 * is deliberately not a migration-time collision axis — consistent with the
 * collision parser's decision to blank function bodies.
 *
 * @returns {{kind: string, text: string}[]}
 */
export function findDynamicRoleMutations(sql) {
  const { hidden } = extractableAndHidden(sql)
  return hidden
    .filter((h) => h.kind === 'string-literal' && looksLikeRoleStatement(h.text))
    .map((h) => ({ kind: h.kind, text: h.text.trim() }))
}

/** Fail-closed guard: refuse when any dynamic role mutation is present. */
export function assertNoDynamicRoleMutations(sql) {
  const found = findDynamicRoleMutations(sql)
  if (found.length) {
    throw new RoleExtractionError(
      `dynamic role mutation(s) cannot be accounted for and must be refused: ${found.map((f) => f.text).join(' | ')}`,
    )
  }
}

/**
 * The role-axis view of a migration.
 *
 * @returns {{
 *   operations: {action: string, kind: 'role', target: string, from?: string, to?: string, members?: string[], grantees?: string[]}[],
 *   ownershipDependencies: {action: 'owner_dependency', role: string, ownerKind: string, ownerTarget: string}[],
 *   dynamicRefusals: {kind: string, text: string}[],
 * }}
 */
export function extractRoleOperations(sql) {
  const { extractable, hidden } = extractableAndHidden(sql)
  const text = extractable
  const operations = []
  const ownershipDependencies = []
  const seen = new Set()
  const add = (op) => {
    const key = `${op.action}|${op.target ?? ''}|${op.from ?? ''}|${op.to ?? ''}|${(op.members ?? []).join(',')}|${(op.grantees ?? []).join(',')}`
    if (seen.has(key)) return
    seen.add(key)
    operations.push(op)
  }

  const run = (re, fn) => {
    re.lastIndex = 0
    let m
    while ((m = re.exec(text)) !== null) fn(m)
  }

  // CREATE ROLE | USER | GROUP  (the three spellings are one PostgreSQL command;
  // covering all three so no role mutation is skipped, while identity stays
  // exact and un-aliased per name).
  run(new RegExp(String.raw`\bcreate\s+(?:role|user|group)\s+(?:if\s+not\s+exists\s+)?(${IDENT})`, 'gi'), (m) => {
    const target = canonicalRoleName(m[1])
    if (target) add({ action: 'create', kind: 'role', target })
  })

  // DROP ROLE a, b  → one drop op per name.
  run(new RegExp(String.raw`\bdrop\s+(?:role|user|group)\s+(?:if\s+exists\s+)?(${IDENT}(?:\s*,\s*${IDENT})*)`, 'gi'), (m) => {
    for (const part of splitRoleList(m[1])) {
      const target = canonicalRoleName(part)
      if (target) add({ action: 'drop', kind: 'role', target })
    }
  })

  // ALTER ROLE x [RENAME TO y] — rename reserves BOTH identities (independent,
  // never aliased); a plain alter reserves the one.
  run(new RegExp(String.raw`\balter\s+(?:role|user|group)\s+(${IDENT})(?:\s+rename\s+to\s+(${IDENT}))?`, 'gi'), (m) => {
    const from = canonicalRoleName(m[1])
    if (!from) return
    if (m[2]) {
      const to = canonicalRoleName(m[2])
      if (to) add({ action: 'rename', kind: 'role', from, to })
    } else {
      add({ action: 'alter', kind: 'role', target: from })
    }
  })

  // Membership GRANT a, b TO c, d  (no `on`, so never a privilege grant).
  run(new RegExp(String.raw`\bgrant\s+(?:admin\s+option\s+for\s+)?(${IDENT}(?:\s*,\s*${IDENT})*)\s+to\s+(${IDENT}(?:\s*,\s*${IDENT})*)(?:\s+with\s+admin\s+option)?(?:\s+granted\s+by\s+${IDENT})?`, 'gi'), (m) => {
    const members = roleNamesFrom(m[1])
    const grantees = roleNamesFrom(m[2])
    if (members.length && grantees.length) add({ action: 'grant_membership', kind: 'role', target: [...members, ...grantees].sort().join(' '), members, grantees })
  })

  // Membership REVOKE a FROM c.
  run(new RegExp(String.raw`\brevoke\s+(?:admin\s+option\s+for\s+)?(${IDENT}(?:\s*,\s*${IDENT})*)\s+from\s+(${IDENT}(?:\s*,\s*${IDENT})*)(?:\s+granted\s+by\s+${IDENT})?`, 'gi'), (m) => {
    const members = roleNamesFrom(m[1])
    const grantees = roleNamesFrom(m[2])
    if (members.length && grantees.length) add({ action: 'revoke_membership', kind: 'role', target: [...members, ...grantees].sort().join(' '), members, grantees })
  })

  // Ownership dependencies: ALTER <kind> <name> OWNER TO <role>. The optional
  // `(…)` skips a function/procedure argument list so `alter function f(…) owner
  // to r` still resolves the owning role. This is a DEPENDENCY, never a write.
  run(new RegExp(String.raw`\balter\s+(foreign\s+table|materialized\s+view|table|view|sequence|function|procedure|schema|type|domain|index|database|tablespace|event\s+trigger)\s+(${QUALIFIED})(?:\s*\([^)]*\))?\s+owner\s+to\s+(${IDENT}|current_user|current_role|session_user)`, 'gi'), (m) => {
    pushOwnership(ownershipDependencies, m[1].toLowerCase().replace(/\s+/g, ' '), m[2], m[3])
  })

  // CREATE SCHEMA … AUTHORIZATION <role> and CREATE DATABASE … OWNER <role>.
  run(new RegExp(String.raw`\bcreate\s+schema\s+(?:if\s+not\s+exists\s+)?(${IDENT})(?:\s+authorization\s+(${IDENT}|current_user|session_user))?`, 'gi'), (m) => {
    if (m[2]) pushOwnership(ownershipDependencies, 'schema', m[1], m[2])
  })
  run(new RegExp(String.raw`\bcreate\s+database\s+(${IDENT})(?:\s+owner\s+(${IDENT}|current_user|session_user))?`, 'gi'), (m) => {
    if (m[2]) pushOwnership(ownershipDependencies, 'database', m[1], m[2])
  })

  const dynamicRefusals = hidden
    .filter((h) => h.kind === 'string-literal' && looksLikeRoleStatement(h.text))
    .map((h) => ({ kind: h.kind, text: h.text.trim() }))

  operations.sort((a, b) => `${a.action} ${a.target}`.localeCompare(`${b.action} ${b.target}`))
  return { operations, ownershipDependencies, dynamicRefusals }
}

/**
 * Collision keys for the role writes only: `"<kind> <canonical>"`, the exact
 * shape a coordinator types into a `db-claim`. Ownership dependencies are
 * deliberately EXCLUDED — they are couplings, not exclusive writes.
 *
 * Fails closed on any dynamic role mutation (see findDynamicRoleMutations).
 *
 * @returns {string[]} e.g. `['role pm_jev_triage_worker']`
 */
export function roleCollisionKeys(sql) {
  assertNoDynamicRoleMutations(sql)
  const { operations } = extractRoleOperations(sql)
  const keys = new Set()
  for (const op of operations) {
    if (op.action === 'rename') {
      keys.add(`role ${op.from}`)
      keys.add(`role ${op.to}`)
      continue
    }
    if (op.action === 'grant_membership' || op.action === 'revoke_membership') {
      for (const name of [...(op.members ?? []), ...(op.grantees ?? [])]) keys.add(`role ${name}`)
      continue
    }
    if (op.target) keys.add(`role ${op.target}`)
  }
  return [...keys].sort()
}

/**
 * Ownership role dependencies only (NOT writes). A consumer pairs these with a
 * role DROP to catch "drop the role a function/table depends on" without ever
 * treating the dependency as an exclusive reservation on the role.
 */
export function roleOwnershipDependencies(sql) {
  return extractRoleOperations(sql).ownershipDependencies
}
