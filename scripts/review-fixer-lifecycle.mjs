#!/usr/bin/env node
// Trusted default-branch adapter for ai-devops #2171. Read-only: it uses the
// existing dispatch parser and claims, never releases claims/version refs.
//   review-fixer-lifecycle.mjs check --source-pr N --issue N --paths-file JSON --worktree PATH
//   review-fixer-lifecycle.mjs retire --fix-pr N --issue N
// Exit 0: no conflict/claim, 3: defer to named owner, 1: unreadable or invalid.
import { readFileSync, lstatSync, realpathSync } from 'node:fs'
import path from 'node:path'
import { pathToFileURL } from 'node:url'
import { ghJson } from './lib/github-transport.mjs'
import { currentRepository } from './lib/repository-identity.mjs'
import { defaultIo, gatherOpenPrObjects, normalizeObject, findDispatchConflicts } from './check-dispatch-collision.mjs'
import { dispatchObjectKeys, roleReadKeys } from './check-pr-object-collisions.mjs'
import { parseAuthorLease } from './lib/lanes/claims.mjs'

const read = (args) => ghJson(args)
const page = (endpoint) => {
  const pages = read(['api', '--paginate', '--slurp', endpoint])
  if (!Array.isArray(pages) || pages.some((p) => !Array.isArray(p))) throw new Error('incomplete paginated metadata')
  return pages.flat()
}
export const liveIo = {
  claims(repo) { return page(`repos/${repo}/issues?state=open&labels=db-claim&per_page=100`).filter((row) => !row.pull_request) },
  pull(repo, number) { return read(['api', `repos/${repo}/pulls/${number}`]) },
  sources(repo, sourcePr) {
    return gatherOpenPrObjects(repo, {
      ...defaultIo,
      listPulls: (r) => defaultIo.listPulls(r).filter((row) => Number(row.number) !== sourcePr),
    })
  },
}

export function proposedAccess(worktree, paths) {
  if (!Array.isArray(paths) || paths.some((p) => typeof p !== 'string' || path.isAbsolute(p)
      || p.includes('\\') || p.includes('\0') || p.split('/').some((part) => part === '..' || part === '')))
    throw new Error('paths must be repository-relative file names')
  const root = realpathSync(worktree)
  const objects = new Set(), reads = new Set()
  for (const filename of paths) {
    if (!filename.startsWith('supabase/migrations/') || !filename.endsWith('.sql')) continue
    const full = path.resolve(root, filename)
    // Reject symlinks at any component; the agent checkout is untrusted input.
    let cursor = root
    for (const part of filename.split('/')) {
      cursor = path.join(cursor, part)
      try { if (lstatSync(cursor).isSymbolicLink()) throw new Error(`symlink in changed migration path ${filename}`) }
      catch (error) { if (error.code === 'ENOENT') { cursor = null; break } throw error }
    }
    if (cursor === null) continue // Deleted migrations carry no new SQL body.
    const sql = readFileSync(full, 'utf8')
    for (const object of dispatchObjectKeys(sql)) objects.add(normalizeObject(object))
    for (const object of roleReadKeys(sql)) reads.add(normalizeObject(object))
  }
  return { objects: [...objects].sort(), reads: [...reads].sort() }
}

export function proposedObjects(worktree, paths) {
  return proposedAccess(worktree, paths).objects
}

export function checkObjects({ repo, sourcePr, objects, reads = [] }, io = liveIo) {
  if (!objects.length && !reads.length) return { state: 'clear', objects: [] }
  const claims = io.claims(repo)
  const proposed = { objects, reads }
  for (const claim of claims) {
    const lease = parseAuthorLease(claim.body)
    const conflicts = findDispatchConflicts(proposed, [{ objects: lease.objects, reads: lease.reads }])
    const overlap = conflicts.objectConflicts.flatMap((row) => row.objects)
    if (overlap.length) return { state: 'defer', reason: `claim #${claim.number} owner ${lease.owner ?? 'legacy/unknown'} holds ${overlap.join(', ')}`, claim: claim.number, owner: lease.owner }
  }
  const conflicts = findDispatchConflicts(proposed, io.sources(repo, sourcePr))
  if (conflicts.objectConflicts.length) {
    const holder = conflicts.objectConflicts[0]
    return { state: 'defer', reason: `object collision with ${holder.label}: ${holder.objects.join(', ')}` }
  }
  return { state: 'clear', objects }
}

export function retirementAudit({ repo, fixPr, issue }, io = liveIo) {
  const pr = io.pull(repo, fixPr)
  if (!pr || Number(pr.number) !== fixPr || pr.head?.ref !== `review-fix/${issue}`
      || pr.head?.repo?.full_name !== repo || !['open', 'closed'].includes(pr.state))
    throw new Error('retirement requires the exact same-repository fixer PR and finding')
  for (const claim of io.claims(repo)) {
    const lease = parseAuthorLease(claim.body)
    if (lease.branch === pr.head.ref) return { state: 'defer', reason: `claim #${claim.number} owner ${lease.owner ?? 'legacy/unknown'} remains associated with ${pr.head.ref}; use its explicit owner-confirmed release procedure`, claim: claim.number, owner: lease.owner }
    if (lease.legacy) throw new Error(`claim #${claim.number} has no readable branch ownership; retirement cannot prove absence of an associated claim`)
  }
  return { state: 'clear', reason: 'No associated structural claim; closing this exact PR releases its open-PR object occupancy. Permanent version refs remain untouched.' }
}

export function main(args = process.argv.slice(2), io = liveIo) {
  try {
    const mode = args.shift(), opts = {}
    while (args.length) {
      const flag = args.shift()
      if (!['--source-pr', '--fix-pr', '--issue', '--paths-file', '--worktree'].includes(flag) || !args.length || opts[flag] !== undefined) throw new Error('invalid lifecycle adapter arguments')
      opts[flag] = args.shift()
    }
    const positive = (flag) => {
      if (!/^[1-9][0-9]*$/.test(opts[flag] ?? '')) throw new Error(`${flag} must be a positive integer`)
      return Number(opts[flag])
    }
    const issue = positive('--issue'), repo = currentRepository(process.env.GITHUB_REPOSITORY || process.env.SHARED_DB_REPO)
    let result
    if (mode === 'check') result = checkObjects({ repo, sourcePr: positive('--source-pr'), ...proposedAccess(opts['--worktree'], JSON.parse(readFileSync(opts['--paths-file'], 'utf8'))) }, io)
    else if (mode === 'retire') result = retirementAudit({ repo, issue, fixPr: positive('--fix-pr') }, io)
    else throw new Error('choose check or retire')
    console.log(JSON.stringify(result))
    return result.state === 'defer' ? 3 : 0
  } catch (error) { console.error(`review-fixer lifecycle: ${error.message}`); return 1 }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) process.exitCode = main()
