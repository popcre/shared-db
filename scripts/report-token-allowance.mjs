#!/usr/bin/env node
// Print how much of each named token's core REST allowance is used
// (counts only, never the token). Workflow steps call this instead of
// shelling out to `gh api rate_limit`, so the read goes through the one shared
// transport (shared-db#6772). Usage: report-token-allowance.mjs ENV_NAME...
// A token that is missing or unreadable prints "<name> unavailable"; the
// report is diagnostic and always exits 0.

import { execFileSync } from 'node:child_process'
import { pathToFileURL } from 'node:url'
import { ghJson } from './lib/github-transport.mjs'

export function allowanceLine(name, body) {
  const core = body?.resources?.core
  if (!Number.isInteger(core?.used) || !Number.isInteger(core?.limit)) return `${name} unavailable`
  return `${name} used=${core.used} limit=${core.limit}`
}

export function reportAllowances(names, { env = process.env, read = ghJson } = {}) {
  return names.map((name) => {
    const token = env[name]
    if (!token) return `${name} unavailable`
    try {
      return allowanceLine(name, read(['api', 'rate_limit'], {
        attempts: 2,
        // Each read is charged to the named token only, never a substituted one.
        executor: (file, argv, options) => execFileSync(file, argv, { ...options, env: { ...env, GH_TOKEN: token } }),
      }))
    } catch {
      return `${name} unavailable`
    }
  })
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  for (const line of reportAllowances(process.argv.slice(2))) console.log(line)
}
