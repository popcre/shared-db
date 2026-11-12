import { test } from 'node:test';
import assert from 'node:assert';
import { manifestDigest, validateManifest } from './lib/designflow-db-release.mjs';

const baseManifest = {
  schema_version: 1,
  repository: 'popcre/designflow-backend',
  production_project_ref: 'qsllyeztdwjgirsysgai',
  requirements: [],
  contracts: [
    { schema: 'dflow_prod', relation: 'users', columns: ['id', 'email'], privileges: [
      { role: 'designflow_prod_backend_runtime', privileges: ['SELECT'] },
    ]},
  ],
};

test('contract digest changes when columns change', () => {
  const changed = { ...baseManifest, contracts: [
    { schema: 'dflow_prod', relation: 'users', columns: ['id', 'email', 'name'], privileges: [
      { role: 'designflow_prod_backend_runtime', privileges: ['SELECT'] },
    ]},
  ]};
  assert.notEqual(manifestDigest(baseManifest), manifestDigest(changed));
});

test('contract digest changes when privileges change', () => {
  const changed = { ...baseManifest, contracts: [
    { schema: 'dflow_prod', relation: 'users', columns: ['id', 'email'], privileges: [
      { role: 'designflow_prod_backend_runtime', privileges: ['SELECT', 'UPDATE'] },
    ]},
  ]};
  assert.notEqual(manifestDigest(baseManifest), manifestDigest(changed));
});

test('contract digest is stable for identical contracts', () => {
  assert.equal(manifestDigest(baseManifest), manifestDigest({ ...baseManifest }));
});

test('contract digest with empty requirements is stable regardless of original requirements', () => {
  const withReqs = { ...baseManifest, requirements: [
    { work_issue: 123, source_pr: 456, migrations: [
      { version: '20260101000000', path: 'supabase/migrations/20260101000000_test.sql', sha256: 'a'.repeat(64) },
    ]},
  ]};
  assert.equal(
    manifestDigest({ ...baseManifest, requirements: [] }),
    manifestDigest({ ...withReqs, requirements: [] }),
  );
});

test('contract digest changes when relation changes', () => {
  const changed = { ...baseManifest, contracts: [
    { schema: 'dflow_prod', relation: 'accounts', columns: ['id', 'email'], privileges: [
      { role: 'designflow_prod_backend_runtime', privileges: ['SELECT'] },
    ]},
  ]};
  assert.notEqual(manifestDigest(baseManifest), manifestDigest(changed));
});

test('contract digest changes when schema changes', () => {
  const changed = { ...baseManifest, contracts: [
    { schema: 'hts_rag', relation: 'users', columns: ['id', 'email'], privileges: [
      { role: 'designflow_prod_backend_runtime', privileges: ['SELECT'] },
    ]},
  ]};
  assert.notEqual(manifestDigest(baseManifest), manifestDigest(changed));
});

test('contract digest changes when role changes', () => {
  const changed = { ...baseManifest, contracts: [
    { schema: 'dflow_prod', relation: 'users', columns: ['id', 'email'], privileges: [
      { role: 'designflow_hts_prod_worker', privileges: ['SELECT'] },
    ]},
  ]};
  assert.notEqual(manifestDigest(baseManifest), manifestDigest(changed));
});

test('validateManifest accepts the base manifest', () => {
  assert.doesNotThrow(() => validateManifest(baseManifest));
});

import { assertSyncPolicy, createAndMergePR, main } from './designflow-contract-sync.mjs';

function syncPolicy(manifests = [baseManifest]) {
  return {
    schema_version: 1, branch: 'develop', manifest_path: '.release/database.json',
    production_project_ref: baseManifest.production_project_ref,
    repositories: manifests.map(manifest => ({
      repository: manifest.repository, contract_manifest_sha256: '0'.repeat(64),
      schemas: ['dflow_prod'], roles: ['designflow_prod_backend_runtime'], required_sources: [],
    })),
  };
}

const secondManifest = { ...baseManifest, repository: 'popcre/designflow-bff' };

function syncAdapters(overrides = {}) {
  return {
    policy: syncPolicy([baseManifest, secondManifest]),
    fetchManifest: repository => structuredClone(repository === baseManifest.repository ? baseManifest : secondManifest),
    findOpenPR: () => null, findOpenIssue: () => null,
    readProduction: async () => [{ production_catalog_proof: {
      production_project_ref: baseManifest.production_project_ref, failures: [], checked_contracts: 1,
    } }],
    createAndMergePR: () => '123', createMismatchIssue: () => {}, ...overrides,
  };
}

test('sync applies the observer schema, role, baseline and repository policy', () => {
  const policy = syncPolicy();
  assert.doesNotThrow(() => assertSyncPolicy(baseManifest.repository, baseManifest, policy));
  for (const [field, value, error] of [
    ['schemas', ['plm'], /Schema is outside/],
    ['roles', ['other_reader'], /Runtime role is outside/],
    ['required_sources', [{ work_issue: 123, source_pr: 456 }], /baseline migration was omitted/],
  ]) {
    const changed = structuredClone(policy);
    changed.repositories[0][field] = value;
    assert.throws(() => assertSyncPolicy(baseManifest.repository, baseManifest, changed), error);
  }
  assert.throws(() => assertSyncPolicy(secondManifest.repository, baseManifest, policy), /repository mismatch/);
});

test('two updates use fresh main and preserve previously merged policy changes', () => {
  let current = syncPolicy([baseManifest, secondManifest]);
  let written;
  const commands = [];
  const io = {
    execFileSync: (command, args) => { commands.push([command, ...args]); },
    readFileSync: () => JSON.stringify(current),
    writeFileSync: (path, value) => { written = JSON.parse(value); },
    gh: args => {
      commands.push(['gh', ...args]);
      if (args[1] === 'create') return 'https://github.com/popcre/shared-db/pull/123';
      current = written;
      return '';
    },
  };
  for (const manifest of [baseManifest, secondManifest]) {
    const digest = manifestDigest(manifest);
    createAndMergePR(manifest.repository, digest, manifest, io);
  }
  assert.equal(current.repositories[0].contract_manifest_sha256, manifestDigest(baseManifest));
  assert.equal(current.repositories[1].contract_manifest_sha256, manifestDigest(secondManifest));
  const checkouts = commands.filter(args => args[1] === 'checkout');
  assert.equal(checkouts.length, 2);
  assert.ok(checkouts.every(args => args.at(-1) === 'origin/main'));
  assert.equal(commands.filter(args => args[1] === 'fetch').length, 2);
  const merges = commands.filter(args => args[0] === 'gh' && args[2] === 'merge');
  assert.equal(merges.length, 2);
  assert.ok(merges.every(args => args.includes('--auto') && !args.includes('--admin')));
});

test('invalid manifest creates an issue and remaining apps continue', async () => {
  const issues = [];
  const results = await main(syncAdapters({
    fetchManifest: repository => repository === baseManifest.repository
      ? { ...baseManifest, unknown_field: true } : secondManifest,
    createMismatchIssue: (...args) => issues.push(args),
  }));
  assert.equal(issues.length, 1);
  assert.equal(issues[0].at(-1), 'manifest validation');
  assert.equal(results[1].status, 'auto-merge-requested');
});

test('issue creation failure preserves original error and continues remaining apps', async () => {
  const priorExitCode = process.exitCode;
  try {
    const results = await main(syncAdapters({
      fetchManifest: repository => {
        if (repository === baseManifest.repository) throw Error('manifest unavailable');
        return secondManifest;
      },
      createMismatchIssue: () => { throw Error('issue service unavailable'); },
    }));
    assert.equal(results[0].error, 'manifest unavailable');
    assert.equal(results[0].issueError, 'issue service unavailable');
    assert.equal(results[1].status, 'auto-merge-requested');
    assert.equal(process.exitCode, 1);
  } finally {
    process.exitCode = priorExitCode;
  }
});

test('publication failures are distinguished from production verification failures', async () => {
  const stages = [];
  const results = await main(syncAdapters({
    createAndMergePR: () => { throw Error('push denied'); },
    createMismatchIssue: (...args) => stages.push(args.at(-1)),
  }));
  assert.ok(stages.every(stage => stage === 'PR publication/auto-merge request'));
  assert.ok(results.every(result => result.error === 'push denied'));
});

test('policy rejection occurs before production verification and PR publication', async () => {
  const policy = syncPolicy();
  policy.repositories[0].schemas = ['plm'];
  const results = await main(syncAdapters({
    policy,
    readProduction: () => assert.fail('must reject before querying production'),
    createAndMergePR: () => assert.fail('must reject before publication'),
  }));
  assert.equal(results[0].stage, 'application policy validation');
  assert.match(results[0].error, /Schema is outside/);
});
