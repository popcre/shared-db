import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { validateManifest, manifestDigest, verifyRequirementSource } from './lib/designflow-db-release.mjs';
import { githubIo, parseQueueScope } from './manage-migration-author-lanes.mjs';
import { readyRecord } from './db-flow/reconcile.mjs';
import { productionCatalogQuery, verifyCatalogProof } from './lib/designflow-db-catalog.mjs';
import { readZipEntries } from './lib/zip-entries.mjs';
import { selectArtifactFiles } from './lib/lanes/review-leases.mjs';
import { fileMatchesLedgerStatements } from './check-applied-migration-edit.mjs';

const CANONICAL = 'popcre/shared-db';
const WORKFLOW = 'shared-supabase-migrations.yml';
const SHA = /^[a-f0-9]{40}$/;
const hash = value => createHash('sha256').update(value).digest('hex');
const policyPath = new URL('../config/designflow-db-releases.json', import.meta.url);

export function releasePolicy(manifest, policy) {
  const m = validateManifest(manifest);
  const app = policy.repositories.find(row => row.repository === m.repository);
  if (!app || policy.schema_version !== 1 || policy.branch !== 'develop' ||
      policy.production_project_ref !== m.production_project_ref) throw Error('Unrecognized release policy/target');
  if (app.contract_manifest_sha256 !== manifestDigest({ ...m, requirements: [] }))
    throw Error('Application contracts do not match the reviewed central contract');
  const declared = new Set(m.requirements.map(r => `${r.work_issue}:${r.source_pr}`));
  for (const required of app.required_sources)
    if (!declared.has(`${required.work_issue}:${required.source_pr}`)) throw Error('Required baseline migration was omitted');
  for (const c of m.contracts) if (!app.schemas.includes(c.schema)) throw Error('Schema is outside this application policy');
  for (const c of m.contracts) for (const p of c.privileges)
    if (!app.roles.includes(p.role)) throw Error('Runtime role is outside this application policy');
  return m;
}

// All effects use authenticated adapters. Application contents are data, never code.
export async function assessRelease({ repository, head, manifest, policy, branch = 'develop' }, io) {
  if (!SHA.test(head) || !['develop', 'main'].includes(branch)) throw Error('Exact application commit and release branch are required');
  const m = releasePolicy(manifest, policy);
  if (m.repository !== repository) throw Error('Application manifest repository mismatch');
  if (branch === 'main' && await io.sourceAllowed?.(repository, head) !== true)
    throw Error('Main release is not an exact reviewed develop-to-main source tree');
  const identity = { repository, branch, head_sha: head, manifest_sha256: manifestDigest(m),
    production_project_ref: m.production_project_ref };
  const current = () => io.applicationHead(repository, branch);
  if (await current() !== head) throw Error('Application develop head changed before assessment');
  const proven = [];
  for (const requirement of m.requirements) {
    const facts = await io.sourceFacts(requirement);
    verifyRequirementSource(requirement, facts);
    const evidence = await io.productionEvidence(requirement, facts);
    if (!evidence) {
      if (branch === 'main') return { ...identity, status: 'waiting', requirement: requirement.work_issue,
        progress: { state: 'develop-database-promotion-required' } };
      if (await current() !== head) throw Error('Application develop head changed before promotion');
      const progress = await io.promote(requirement, facts);
      return { ...identity, status: 'waiting', requirement: requirement.work_issue, progress };
    }
    proven.push(evidence);
  }
  const catalog = await io.catalog(m.contracts, m.production_project_ref);
  if (await current() !== head) throw Error('Application develop head changed before readiness publication');
  return { ...identity, status: 'ready', requirements: proven, catalog_sha256: hash(JSON.stringify(catalog)) };
}

function command(args, { input, timeout = 60_000 } = {}) {
  try { return execFileSync('gh', args, { encoding: 'utf8', input, timeout, maxBuffer: 20 * 1024 * 1024, stdio: ['pipe', 'pipe', 'pipe'] }); }
  catch { throw Error(`GitHub operation refused or unavailable: ${args[0]}`); }
}
function api(endpoint, body) {
  const args = ['api', endpoint];
  if (body !== undefined) args.push('--method', 'POST', '--input', '-');
  const output = command(args, { input: body === undefined ? undefined : JSON.stringify(body) });
  return output.trim() ? JSON.parse(output) : null;
}
function pages(endpoint, limit = 5) {
  const rows = [];
  for (let page = 1; page <= limit; page++) {
    const batch = api(`${endpoint}${endpoint.includes('?') ? '&' : '?'}per_page=100&page=${page}`);
    if (!Array.isArray(batch)) throw Error('GitHub page is not an array');
    rows.push(...batch);
    if (batch.length < 100) return rows;
  }
  throw Error('GitHub pagination limit reached; completeness is not proven');
}
export function workflowRuns(read, endpoint, limit = 5) {
  const runs = [];
  for (let page = 1; page <= limit; page++) {
    const response = read(`${endpoint}${endpoint.includes('?') ? '&' : '?'}per_page=100&page=${page}`);
    if (!response || !Array.isArray(response.workflow_runs)) throw Error('Workflow run page is unreadable');
    runs.push(...response.workflow_runs);
    if (response.workflow_runs.length < 100) return runs;
  }
  throw Error('Workflow run pagination bound reached; discovery is incomplete');
}

export function artifactContainsSource(requirement, files) {
  const manifest = JSON.parse(files.get('migration-content-manifest.json'));
  const catalog = JSON.parse(files.get('production-catalog-verification.json'));
  const expected = requirement.migrations.map(m => m.version).sort().join(',');
  return Array.isArray(catalog?.allowlist) && catalog.allowlist.slice().sort().join(',') === expected &&
    !!manifest && !Array.isArray(manifest) && requirement.migrations.every(m => manifest[m.version] === m.sha256);
}

function content(repository, path, ref) {
  const data = api(`repos/${repository}/contents/${path}?ref=${ref}`);
  if (data.type !== 'file' || data.encoding !== 'base64' || data.size > 8 * 1024 * 1024)
    throw Error('Source content is not a bounded ordinary file');
  return Buffer.from(data.content.replace(/\s/g, ''), 'base64').toString('utf8');
}

export function dispatchTitle(manifest, mode) {
  if (!['dry-run', 'apply'].includes(mode) || manifest.target !== 'preview' || !SHA.test(manifest.commit_sha) ||
      !/^[1-9][0-9]*$/.test(String(manifest.merged_preview_source_pr)) ||
      !/^\d{14}(?:,\d{14})*$/.test(manifest.preview_allowlist))
    throw Error('Only canonical preview dispatch is permitted');
  return `DB preview ${mode} ${manifest.commit_sha} PR${manifest.merged_preview_source_pr} ${manifest.preview_allowlist}`;
}

function sourceFacts(requirement) {
  const pr = api(`repos/${CANONICAL}/pulls/${requirement.source_pr}`);
  const linked = githubIo.closingIssuesForPr(requirement.source_pr);
  if (linked.length !== 1 || Number(linked[0].number) !== requirement.work_issue)
    throw Error('Canonical source must link exclusively to its required work issue');
  const main = api(`repos/${CANONICAL}/commits/main`).sha;
  const comparison = api(`repos/${CANONICAL}/compare/${pr.merge_commit_sha}...${main}`);
  const files = pages(`repos/${CANONICAL}/pulls/${requirement.source_pr}/files`)
    .filter(row => row.filename.startsWith('supabase/migrations/')).map(row => {
      if (row.status !== 'added') throw Error('Release migration must be newly authored, never rewritten');
      const source = content(CANONICAL, row.filename, pr.head.sha);
      if (content(CANONICAL, row.filename, main) !== source) throw Error('Migration changed after source approval');
      return { path: row.filename, content: source };
    });
  return { repository: pr.base.repo.full_name, base_branch: pr.base.ref, merged: pr.merged === true,
    source_pr: pr.number, work_issue: Number(linked[0].number), head_sha40: pr.head.sha,
    merge_sha40: pr.merge_commit_sha, merge_in_main: ['ahead', 'identical'].includes(comparison.status) && comparison.behind_by === 0, files };
}

export function verifyApplyReceipt(requirement, facts, receipt, ledger) {
  const keys = ['schema_version', 'work_issue', 'source_pr', 'source_head_sha', 'source_merge_sha',
    'production_main_sha', 'production_run_id', 'production_run_attempt', 'artifact_id', 'artifact_digest',
    'migration_hashes', 'ledger_fingerprints', 'catalog_sha256', 'captured_at'];
  if (!receipt || Object.keys(receipt).length !== keys.length || keys.some(k => !Object.hasOwn(receipt, k)) || receipt.schema_version !== 1 ||
      receipt.work_issue !== requirement.work_issue || receipt.source_pr !== requirement.source_pr ||
      receipt.source_head_sha !== facts.head_sha40 || receipt.source_merge_sha !== facts.merge_sha40 ||
      !SHA.test(receipt.production_main_sha) || !/^sha256:[a-f0-9]{64}$/.test(receipt.artifact_digest) ||
      !/^[a-f0-9]{64}$/.test(receipt.catalog_sha256) ||
      !['production_run_id', 'production_run_attempt', 'artifact_id'].every(k => Number.isSafeInteger(receipt[k]) && receipt[k] > 0) ||
      !Number.isFinite(Date.parse(receipt.captured_at)) || Date.parse(receipt.captured_at) > Date.now()) throw Error('Malformed immutable production receipt');
  const expected = requirement.migrations.map(m => m.version).sort().join(',');
  for (const data of [receipt.migration_hashes, receipt.ledger_fingerprints, ledger])
    if (!data || Array.isArray(data) || Object.keys(data).sort().join(',') !== expected) throw Error('Receipt/ledger migration set differs');
  for (const m of requirement.migrations)
    if (receipt.migration_hashes[m.version] !== m.sha256 || !/^[a-f0-9]{64}$/.test(receipt.ledger_fingerprints[m.version]) ||
        receipt.ledger_fingerprints[m.version] !== ledger[m.version]) throw Error('Applied migration or live ledger fingerprint changed');
  return { work_issue: requirement.work_issue, source_pr: requirement.source_pr, run_id: receipt.production_run_id,
    artifact_id: receipt.artifact_id, artifact_digest: receipt.artifact_digest };
}

function verifyProducer(run) {
  if (run.path !== `.github/workflows/${WORKFLOW}` || run.event !== 'workflow_dispatch' || run.status !== 'completed' ||
      run.conclusion !== 'success' || !githubIo.mergeCommitInMain(run.head_sha)) return false;
  const jobs = api(`repos/${CANONICAL}/actions/runs/${run.id}/attempts/${run.run_attempt}/jobs?per_page=100`);
  if (jobs.total_count > 100) throw Error('Production producer jobs exceed bounded verification');
  for (const name of ['SQL migration guards', 'Production apply review (immutable evidence + hard guards)', 'Production apply (automatic evidence gates)'])
    if (jobs.jobs.filter(j => j.name === name && j.status === 'completed' && j.conclusion === 'success').length !== 1) return false;
  return true;
}

export function verifyAppliedFiles(requirement, files) {
  const manifest = JSON.parse(files.get('migration-content-manifest.json'));
  if (!manifest || Array.isArray(manifest) || requirement.migrations.some(m => manifest[m.version] !== m.sha256))
    throw Error('Applied migration hashes differ from required source');
  const catalog = JSON.parse(files.get('production-catalog-verification.json'));
  const expected = requirement.migrations.map(m => m.version).sort();
  if (catalog.enforcing !== true || !Array.isArray(catalog.errors) || catalog.errors.length ||
      catalog.allowlist?.slice().sort().join(',') !== expected.join(',')) throw Error('Enforced production catalog proof did not pass');
  const versions = name => new Set(String(files.get(name) ?? '').split(/\r?\n/).flatMap(line => {
    const match = /^\s*(?:\d{14})?\s*\|\s*(\d{14})\s*\|/.exec(line);
    return match ? [match[1]] : [];
  }));
  const before = versions('production-ledger-before.txt'), after = versions('production-ledger-after.txt');
  if (!after.size || [...before].some(v => !after.has(v)) ||
      [...after].filter(v => !before.has(v)).sort().join(',') !== expected.join(',')) throw Error('Production ledger delta differs from the exact required migration set');
  return Object.fromEntries(requirement.migrations.map(m => [m.version, manifest[m.version]]));
}

async function ledgerFingerprints(requirement, facts) {
  const literal = JSON.stringify(requirement.migrations.map(m => m.version)).replaceAll("'", "''");
  const rows = await readProduction(`BEGIN READ ONLY;
    SELECT coalesce(jsonb_object_agg(s.version, jsonb_build_object('fingerprint',encode(sha256(convert_to(array_to_json(s.statements)::text, 'UTF8')), 'hex'),'statements',s.statements)), '{}'::jsonb) AS ledger
    FROM supabase_migrations.schema_migrations s
    JOIN jsonb_array_elements_text('${literal}'::jsonb) wanted(version) ON wanted.version=s.version;
    COMMIT;`);
  if (rows.length !== 1 || !rows[0].ledger || Array.isArray(rows[0].ledger)) throw Error('Live migration ledger is unreadable');
  const fingerprints = {};
  for (const m of requirement.migrations) {
    const live = rows[0].ledger[m.version];
    if (!live) continue;
    const source = facts.files.find(f => f.path === m.path)?.content;
    if (!fileMatchesLedgerStatements(source, live.statements)) {
      // The existing reviewed atomic applier has one explicit outer-transaction
      // transformation. Reuse its exact policy/parser; never strip SQL ad hoc.
      let expected;
      try { expected = JSON.parse(execFileSync('python', ['-c',
        'import hashlib,json,sys;from pathlib import Path;sys.path.insert(0,"scripts");from atomic_migration_apply import load_candidate;p,_,_,s=load_candidate(Path("supabase/migrations"),sys.argv[1],"production");print(json.dumps({"sha256":hashlib.sha256(p.read_bytes()).hexdigest(),"statements":s}))', m.version],
        { encoding: 'utf8', timeout: 10_000, maxBuffer: 8 * 1024 * 1024, stdio: ['pipe', 'pipe', 'pipe'] })); }
      catch { throw Error('Current production ledger statements differ from exact canonical source'); }
      if (expected.sha256 !== m.sha256 || JSON.stringify(expected.statements) !== JSON.stringify(live.statements)) throw Error('Current production ledger statements differ from the authorized atomic source');
    }
    fingerprints[m.version] = live.fingerprint;
  }
  return fingerprints;
}

async function productionEvidence(requirement, facts) {
  const ledger = await ledgerFingerprints(requirement, facts);
  const ref = `refs/designflow-db-apply-receipts/${requirement.work_issue}/${requirement.source_pr}/${facts.head_sha40}`;
  const archived = githubIo.readRef(ref);
  if (archived) {
    const message = githubIo.getCommit(archived)?.message, prefix = 'designflow-db-apply-receipt ';
    if (!message?.startsWith(prefix)) throw Error('Production receipt has unknown provenance');
    const receipt = JSON.parse(message.slice(prefix.length));
    const result = verifyApplyReceipt(requirement, facts, receipt, ledger);
    const run = api(`repos/${CANONICAL}/actions/runs/${receipt.production_run_id}/attempts/${receipt.production_run_attempt}`);
    if (run.head_sha !== receipt.production_main_sha || !verifyProducer(run)) throw Error('Archived production producer no longer verifies');
    return result;
  }
  if (Object.keys(ledger).length !== requirement.migrations.length) return null;
  const scope = parseQueueScope(api(`repos/${CANONICAL}/issues/${requirement.work_issue}`).body);
  const comments = pages(`repos/${CANONICAL}/issues/${requirement.work_issue}/comments`);
  const mentioned = comments.flatMap(row => [...row.body.matchAll(/https:\/\/github\.com\/popcre\/shared-db\/actions\/runs\/([1-9][0-9]*)/g)].map(m => m[1]));
  const source = api(`repos/${CANONICAL}/pulls/${requirement.source_pr}`);
  if (!source.merged_at || source.head.sha !== facts.head_sha40) throw Error('Production discovery source changed');
  const since = encodeURIComponent(`>=${source.merged_at}`);
  const discovered = workflowRuns(api, `repos/${CANONICAL}/actions/workflows/${WORKFLOW}/runs?event=workflow_dispatch&status=success&created=${since}`);
  const expectedSuffix = ` PR${requirement.source_pr} ${requirement.migrations.map(m => m.version).join(',')}`;
  const ids = [...new Set([...mentioned, ...discovered.filter(r => r.display_title?.startsWith('DB production apply ') && r.display_title.endsWith(expectedSuffix)).map(r => String(r.id))])];
  if (ids.length > 50) throw Error('Production evidence candidates exceed bounded verification');
  const verified = [];
  for (const id of ids) {
    const run = api(`repos/${CANONICAL}/actions/runs/${id}`);
    if (!verifyProducer(run)) continue;
    const artifacts = api(`repos/${CANONICAL}/actions/runs/${id}/artifacts?per_page=100`);
    if (artifacts.total_count > 100) throw Error('Artifact pagination required');
    for (const artifact of artifacts.artifacts.filter(a => a.name === `production-migration-apply-${run.head_sha}` && a.expired === false)) {
      const evidence = { schema_version: 1, work_issue: requirement.work_issue, merge_pr: requirement.source_pr,
        merge_sha: facts.merge_sha40, application_repository: scope.applicationReturnTo,
        production_evidence: run.html_url, production_commit_sha: run.head_sha,
        production_artifact_id: artifact.id, production_artifact_digest: artifact.digest,
        live_assertion: scope.liveAssertion, environment: 'production', verified_at: new Date().toISOString() };
      if (artifact.workflow_run?.head_sha !== run.head_sha || Number(artifact.workflow_run?.id) !== run.id) throw Error('Production artifact producer changed');
      let bytes;
      try { bytes = execFileSync('gh', ['api', `repos/${CANONICAL}/actions/artifacts/${artifact.id}/zip`],
        { encoding: null, timeout: 60_000, maxBuffer: 16 * 1024 * 1024, stdio: ['pipe', 'pipe', 'pipe'] }); }
      catch { throw Error('Production artifact download is unavailable'); }
      if (artifact.digest !== `sha256:${hash(bytes)}`) throw Error('Production archive digest differs');
      const files = selectArtifactFiles(readZipEntries(bytes), ['production-apply.txt', 'production-ledger-before.txt', 'production-ledger-after.txt',
        'migration-content-manifest.json', 'production-catalog-verification.json']);
      if (!artifactContainsSource(requirement, files)) continue;
      const actualHashes = verifyAppliedFiles(requirement, files);
      const verifier = { ...githubIo, readArtifactFiles: () => files };
      if (verifier.verifyProductionApply(evidence) !== true) throw Error('Native production artifact verifier refused');
      const receipt = { schema_version: 1, work_issue: requirement.work_issue, source_pr: requirement.source_pr,
        source_head_sha: facts.head_sha40, source_merge_sha: facts.merge_sha40, production_main_sha: run.head_sha,
        production_run_id: run.id, production_run_attempt: run.run_attempt, artifact_id: artifact.id, artifact_digest: artifact.digest,
        migration_hashes: actualHashes, ledger_fingerprints: ledger, catalog_sha256: hash(files.get('production-catalog-verification.json')),
        captured_at: new Date().toISOString() };
      verifyApplyReceipt(requirement, facts, receipt, ledger);
      verified.push({ receipt, result: { work_issue: requirement.work_issue, source_pr: requirement.source_pr, run_id: run.id,
        artifact_id: artifact.id, artifact_digest: artifact.digest } });
    }
  }
  if (verified.length > 1) throw Error('Ambiguous production evidence requires reconciliation');
  if (!verified.length) return null;
  const candidate = verified[0];
  const sha = githubIo.makeOwnerCommit('designflow-db-apply-receipt ' + JSON.stringify(candidate.receipt));
  if (!githubIo.createRef(ref, sha) || githubIo.readRef(ref) !== sha) throw Error('Immutable application receipt could not be preserved');
  return candidate.result;
}

// Two bounded scheduled passes sequence dry-run then apply; no sleeping worker,
// no second SQL executor, and an uncertain dispatch is never replayed.
function promote(requirement) {
  const prepared = JSON.parse(execFileSync(process.execPath,
    ['scripts/manage-migration-author-lanes.mjs', '--prepare-preview-dispatch', String(requirement.work_issue)],
    { encoding: 'utf8', timeout: 120_000, maxBuffer: 1024 * 1024 }));
  const ready = readyRecord(prepared.record);
  if (prepared.status !== 'PREVIEW_READY' || ready.route !== 'merged_rehearsal' ||
      ready.pr !== requirement.source_pr || ready.manifest.preview_allowlist.split(',').sort().join(',') !== requirement.migrations.map(m => m.version).sort().join(','))
    throw Error('Stored native preview instruction does not match the release requirement');
  if (api(`repos/${CANONICAL}/commits/main`).sha !== ready.manifest.commit_sha) throw Error('Canonical main changed before dispatch');
  for (const mode of ready.mode_sequence) {
    const ref = `refs/designflow-db-dispatches/${ready.ready_id}/${mode}`;
    const prior = githubIo.readRef(ref);
    const title = dispatchTitle(ready.manifest, mode);
    const runs = workflowRuns(api, `repos/${CANONICAL}/actions/workflows/${WORKFLOW}/runs?event=workflow_dispatch&head_sha=${ready.manifest.commit_sha}`)
      .filter(r => r.head_sha === ready.manifest.commit_sha && r.display_title === title);
    if (runs.length > 1) throw Error('Ambiguous native dispatch run; never guess');
    if (prior) {
      const message = githubIo.getCommit(prior)?.message;
      const prefix = 'designflow-db-dispatch ';
      if (!message?.startsWith(prefix)) throw Error('Malformed preserved dispatch');
      const recorded = JSON.parse(message.slice(prefix.length));
      if (recorded.ready_id !== ready.ready_id || recorded.mode !== mode || recorded.title !== title) throw Error('Preserved dispatch identity changed');
      const run = runs[0];
      if (!run || Date.parse(run.created_at) < Date.parse(recorded.created_at) - 1000)
        throw Error('Preserved dispatch has no authenticated run; reconcile before retry');
      if (run.status !== 'completed') return { state: 'running', mode, run_id: run.id };
      if (run.conclusion !== 'success') throw Error('Native rehearsal failed; repair its cause before recovery');
      continue;
    }
    if (runs.length) throw Error('Existing run has no release dispatch custody; reconcile before adoption');
    const record = { ready_id: ready.ready_id, mode, title, created_at: new Date().toISOString() };
    const owner = githubIo.makeOwnerCommit('designflow-db-dispatch ' + JSON.stringify(record));
    if (!githubIo.createRef(ref, owner) || githubIo.readRef(ref) !== owner) throw Error('Dispatch custody could not be preserved');
    // Deliberately one write attempt. A timeout remains an unresolved dispatch.
    api(`repos/${CANONICAL}/actions/workflows/${WORKFLOW}/dispatches`, { ref: 'main', inputs: { ...ready.manifest, mode } });
    return { state: 'dispatched', mode, ready_id: ready.ready_id };
  }
  return { state: 'awaiting-production-evidence', ready_id: ready.ready_id };
}

export async function runObserver(policy, io) {
  const results = [];
  for (const app of policy.repositories) for (const branch of policy.release_branches ?? ['develop']) {
    let head;
    try {
      head = await io.applicationHead(app.repository, branch);
      if (!SHA.test(head)) throw Error('Application head is not an exact SHA');
      await io.status(app.repository, head, 'pending', 'Checking required production database changes');
      const manifest = await io.manifest(app.repository, head);
      const result = await assessRelease({ repository: app.repository, head, manifest, policy, branch }, io);
      await io.status(app.repository, head, result.status === 'ready' ? 'success' : 'pending',
        result.status === 'ready' ? 'Required production database changes and contracts verified' : 'Required database promotion remains pending');
      results.push(result);
    } catch (error) {
      if (head && SHA.test(head)) await io.status(app.repository, head, 'failure', 'Database readiness could not be proven; see central run');
      results.push({ repository: app.repository, branch, head_sha: head, status: 'blocked', reason: error.message });
    }
  }
  return results;
}

async function readProduction(query) {
  const project = 'qsllyeztdwjgirsysgai';
  if (!process.env.SUPABASE_ACCESS_TOKEN)
    throw Error('Authenticated production catalog access is unavailable');
  // Target comes from reviewed central policy and the fixed HTTPS endpoint.
  // A project label returned by SQL is never used as connection authority.
  const response = await fetch(`https://api.supabase.com/v1/projects/${project}/database/query`, {
    method: 'POST', redirect: 'error', signal: AbortSignal.timeout(30_000),
    headers: { Authorization: `Bearer ${process.env.SUPABASE_ACCESS_TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query, read_only: true }),
  });
  if (!response.ok) throw Error(`Production catalog service refused (${response.status})`);
  const body = await response.json();
  if (!Array.isArray(body)) throw Error('Production catalog envelope changed');
  return body;
}

async function catalog(contracts, project) {
  if (project !== 'qsllyeztdwjgirsysgai') throw Error('Production catalog target mismatch');
  const rows = await readProduction(productionCatalogQuery(contracts));
  if (rows.length !== 1) throw Error('Production catalog envelope changed');
  return verifyCatalogProof(contracts, rows[0].production_catalog_proof);
}

export async function main() {
  if (process.argv.slice(2).join(' ') !== '--observe' || process.env.GITHUB_REPOSITORY !== CANONICAL || process.env.GITHUB_REF !== 'refs/heads/main')
    throw Error('Observer executes only from canonical main with --observe');
  const policy = JSON.parse(readFileSync(policyPath, 'utf8'));
  const remaining = api('rate_limit').resources.core.remaining;
  if (!Number.isSafeInteger(remaining) || remaining < 1000) throw Error('GitHub API reserve is unavailable');
  const factsCache = new Map(), evidenceCache = new Map();
  const memo = (cache, key, fn) => {
    if (!cache.has(key)) cache.set(key, fn());
    return cache.get(key);
  };
  const url = `https://github.com/${CANONICAL}/actions/runs/${process.env.GITHUB_RUN_ID}`;
  const io = {
    applicationHead: (repo, branch = 'develop') => api(`repos/${repo}/git/ref/heads/${branch}`).object.sha,
    sourceAllowed: (repo, mainHead) => {
      const commit = api(`repos/${repo}/commits/${mainHead}`);
      const pulls = pages(`repos/${repo}/commits/${mainHead}/pulls`);
      const eligible = pulls.filter(p => p.merged_at && p.merge_commit_sha === mainHead && p.base.ref === 'main' &&
        p.head.ref === 'develop' && p.base.repo.full_name === repo && p.head.repo?.full_name === repo);
      if (eligible.length !== 1) return false;
      return api(`repos/${repo}/commits/${eligible[0].head.sha}`).commit.tree.sha === commit.commit.tree.sha;
    },
    manifest: (repo, head) => JSON.parse(content(repo, policy.manifest_path, head)),
    sourceFacts: requirement => memo(factsCache, requirement.source_pr, () => sourceFacts(requirement)),
    productionEvidence: (requirement, facts) => memo(evidenceCache, requirement.source_pr, () => productionEvidence(requirement, facts)),
    promote,
    catalog,
    status: (repo, head, state, description) => api(`repos/${repo}/statuses/${head}`, { state, context: policy.status_context, description, target_url: url }),
  };
  const results = await runObserver(policy, io);
  process.stdout.write(JSON.stringify(results, null, 2) + '\n');
  if (results.some(r => r.status !== 'ready')) process.exitCode = 1;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href)
  main().catch(() => { process.stderr.write('Database release observer refused; no readiness was authorized.\n'); process.exitCode = 1; });
