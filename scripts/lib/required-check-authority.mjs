import { createHash } from 'node:crypto'

export class RequiredCheckAuthorityError extends Error {}
const refuse = (message) => { throw new RequiredCheckAuthorityError(message) }
const named = (value) => typeof value === 'string' && value.trim().length > 0
const appId = (value) => value === null || value === -1 ? null : (Number.isSafeInteger(value) && value > 0 ? value : refuse('required check producer identity is unreadable'))
export function normalizeRequirements(checks) {
  if (!Array.isArray(checks)) refuse('required checks are not a complete list')
  const unique = new Map()
  for (const check of checks) {
    if (!named(check?.context)) refuse('required check context is unreadable')
    const item = { context: check.context, app_id: appId(check.app_id) }
    unique.set(JSON.stringify(item), item)
  }
  return [...unique.values()].sort((a, b) => a.context.localeCompare(b.context) || (a.app_id ?? -1) - (b.app_id ?? -1))
}

// Ref.branchProtectionRule resolves the actual classic rule for this branch.
// /rules/branches resolves applicable ACTIVE repository AND inherited rulesets.
// Neither a hand-authored manifest nor an expiring attestation authorizes a merge.
// GitHub itself performs the final atomic policy enforcement; callers must read
// this again under the merge lock and must never use an administrative bypass.
//
// TOKEN PERMISSIONS: the two reads below require the workflow token to have
// `contents:read` (or write) for the GraphQL ref/branchProtectionRule query and
// `administration:read` is NOT needed — the REST /rules/branches endpoint is
// served under the repository's contents permission. A 403 on either read
// causes every merge to refuse (fail-closed). Verified live 2026-09-25 under
// github.token with contents:write, statuses:write, checks:read, actions:write.
export function readEffectiveRequiredChecks({ repo, branch = 'main', read, now = () => new Date() }) {
  if (!/^[\w.-]+\/[\w.-]+$/.test(repo) || !named(branch)) refuse('repository or branch identity is invalid')
  const [owner, name] = repo.split('/')
  const query = 'query($owner:String!,$name:String!,$ref:String!){repository(owner:$owner,name:$name){databaseId nameWithOwner ref(qualifiedName:$ref){name target{oid} branchProtectionRule{id requiresStatusChecks requiresStrictStatusChecks requiredStatusCheckContexts requiredStatusChecks{context app{databaseId}}}}}}'
  const response = read(['api', 'graphql', '-f', `query=${query}`, '-f', `owner=${owner}`, '-f', `name=${name}`, '-f', `ref=refs/heads/${branch}`])
  if (response?.errors?.length) refuse('effective branch protection GraphQL read returned errors')
  const repository = response?.data?.repository
  if (!Number.isSafeInteger(repository?.databaseId) || repository.databaseId <= 0 || repository.nameWithOwner?.toLowerCase() !== repo.toLowerCase() || repository.ref?.name !== branch || !/^[a-f0-9]{40}$/.test(repository.ref?.target?.oid ?? '')) refuse('effective branch protection repository/branch identity is unknown')
  const protection = repository.ref.branchProtectionRule
  const requirements = []
  if (protection !== null) {
    if (!named(protection?.id) || typeof protection.requiresStatusChecks !== 'boolean' || typeof protection.requiresStrictStatusChecks !== 'boolean' || !Array.isArray(protection.requiredStatusCheckContexts) || !Array.isArray(protection.requiredStatusChecks)) refuse('effective classic protection is incomplete')
    if (protection.requiresStatusChecks) {
      for (const item of protection.requiredStatusChecks) requirements.push({ context: item.context, app_id: item.app === null ? null : item.app?.databaseId })
      const contexts = new Set(requirements.map((item) => item.context))
      if (protection.requiredStatusCheckContexts.some((context) => !contexts.has(context)) || requirements.some((item) => !protection.requiredStatusCheckContexts.includes(item.context))) refuse('classic context and producer lists disagree')
    }
  }
  const perPage = 100
  const pages = read(['api', '--paginate', '--slurp', `repos/${repo}/rules/branches/${encodeURIComponent(branch)}?per_page=${perPage}`])
  if (!Array.isArray(pages) || !pages.length || pages.some((page) => !Array.isArray(page))) refuse('effective ruleset read is incomplete')
  // Each non-last page must be full; a short non-last page means gh stopped
  // paginating early and we are about to under-count requirements (fail-open).
  for (let i = 0; i < pages.length - 1; i++) {
    if (pages[i].length !== perPage) refuse('effective ruleset pagination is incomplete')
  }
  const rules = pages.flat()
  for (const rule of rules) {
    if (!named(rule?.type) || !Number.isSafeInteger(rule.ruleset_id) || !named(rule.ruleset_source_type) || !named(rule.ruleset_source)) refuse('effective ruleset source identity is incomplete')
    if (rule.type === 'required_status_checks') {
      if (!Array.isArray(rule.parameters?.required_status_checks)) refuse('effective ruleset check list is unreadable')
      for (const item of rule.parameters.required_status_checks) requirements.push({ context: item.context, app_id: item.integration_id })
    }
  }
  const checks = normalizeRequirements(requirements)
  if (!checks.length) refuse('effective policy requires no checks; refusing unknown or removed protection')
  const sources = { classic: protection, rulesets: rules }
  const revision = createHash('sha256').update(JSON.stringify({ repository_id: repository.databaseId, repository: repository.nameWithOwner, branch, sources })).digest('hex')
  return { schema_version: 1, mode: 'live-effective-settings', repository_id: repository.databaseId, repository: repository.nameWithOwner, branch, base_sha: repository.ref.target.oid, capturedIso: now().toISOString(), revision, sources, checks }
}
