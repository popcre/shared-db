#!/usr/bin/env node
// Counts-only receipt (shared-db#6772): which hourly allowance did the
// DesignFlow observer spend? Prints core used/limit for the operator token and
// the App read token. Never prints a token.
import { execFileSync } from 'node:child_process'
import { runGitHubCommand } from './lib/github-transport.mjs'

for (const name of ['OPERATOR_TOKEN', 'READ_TOKEN']) {
  const token = process.env[name]
  if (!token) { console.log(`${name} unavailable`); continue }
  try {
    const out = runGitHubCommand(['api', 'rate_limit'], {
      attempts: 1,
      executor: (file, argv, options) => execFileSync(file, argv, { ...options, env: { ...process.env, DFLOW_GITHUB_READ_TOKEN: '', GH_TOKEN: token } }),
    })
    const { used, limit } = JSON.parse(String(out)).resources.core
    console.log(`${name} used=${used} limit=${limit}`)
  } catch { console.log(`${name} unavailable`) }
}
