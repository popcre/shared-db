function contextsFrom(value, source) {
  const contexts = value?.contexts
  if (!Array.isArray(contexts) || contexts.some((name) => typeof name !== 'string' || !name.trim()) || new Set(contexts).size !== contexts.length) {
    throw new Error(`${source} required checks are absent or malformed`)
  }
  const checks = value?.checks
  if (!Array.isArray(checks) || checks.some((check) => typeof check?.context !== 'string' || !check.context.trim()) || new Set(checks.map((check) => check.context)).size !== checks.length || checks.length !== contexts.length || checks.some((check) => !contexts.includes(check.context))) {
    throw new Error(`${source} check identities disagree with required contexts`)
  }
  return contexts
}

/** Read the same protected checks through the branch endpoint when the Actions token lacks Administration:read. */
export function readRequiredCheckContexts({ protectedChecks, branch, branchRules }) {
  let authoritative = null
  try {
    authoritative = contextsFrom(protectedChecks(), 'branch protection')
  } catch (error) {
    if (!/Resource not accessible by integration \(HTTP 403\)/.test(String(error?.message ?? error))) throw error
  }

  const current = branch()
  if (current?.name !== 'main' || current?.protected !== true || current?.protection?.enabled !== true) {
    throw new Error('main branch protection readback is absent or ambiguous')
  }
  const alternate = contextsFrom(current.protection.required_status_checks, 'main branch readback')
  const rules = branchRules()
  if (!Array.isArray(rules) || rules.length !== 0) {
    throw new Error('main branch ruleset readback is absent or nonempty; required checks need independent reconciliation')
  }
  if (authoritative && (authoritative.length !== alternate.length || authoritative.some((name) => !alternate.includes(name)))) {
    throw new Error('main branch required checks disagree with branch protection')
  }
  return alternate
}
