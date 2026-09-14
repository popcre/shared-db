// Issue #2437: guard the ANALYSIS path, not just the migration path.
//
// 1. checkProposalBody: an issue carrying the `destructive-proposal` label must
//    carry every checklist heading from .github/ISSUE_TEMPLATE/destructive-proposal.md
//    in its BODY, each with real content (the queue reads bodies, not comments).
// 2. findDestructiveSql: added SQL anywhere in a pull request (outside migrations
//    and the disposable test fixtures, which have their own guards) may not
//    introduce DROP / TRUNCATE / VACUUM FULL / unqualified DELETE unless the same
//    file's added lines name the tracking issue with `-- destructive-proposal: #<n>`.

export const PROPOSAL_LABEL = 'destructive-proposal'

export const REQUIRED_HEADINGS = [
  'Proposed action',
  'Observation window',
  'Positive control',
  'Second independent source',
  'Evidence class',
  'Earliest action date',
]

function stripHtmlComments(text) {
  return String(text ?? '').replace(/<!--[\s\S]*?-->/g, '')
}

export function checkProposalBody(body) {
  const text = stripHtmlComments(body).replace(/\r\n/g, '\n')
  const sections = new Map()
  let current = null
  for (const line of text.split('\n')) {
    const heading = line.match(/^#{1,6}\s+(.+?)\s*#*\s*$/)
    if (heading) {
      current = heading[1].trim().toLowerCase()
      if (!sections.has(current)) sections.set(current, '')
      continue
    }
    if (current !== null) sections.set(current, sections.get(current) + line + '\n')
  }
  const missing = []
  const empty = []
  for (const name of REQUIRED_HEADINGS) {
    const key = name.toLowerCase()
    if (!sections.has(key)) missing.push(name)
    else if (!sections.get(key).trim()) empty.push(name)
  }
  return { ok: missing.length === 0 && empty.length === 0, missing, empty }
}

export function isGuardedSqlPath(path) {
  const p = String(path).replace(/\\/g, '/')
  if (!p.toLowerCase().endsWith('.sql')) return false
  if (p.startsWith('supabase/migrations/')) return false
  if (p.startsWith('supabase/tests/')) return false
  return true
}

const DESTRUCTIVE_PATTERNS = [
  { kind: 'DROP', re: /\bdrop\s+(?:table|schema|index|materialized\s+view|view|column|database)\b/i },
  { kind: 'TRUNCATE', re: /\btruncate\b/i },
  { kind: 'VACUUM FULL', re: /\bvacuum\s*(?:\(\s*[^)]*\bfull\b[^)]*\)|full\b)/i },
]

const MARKER = /--\s*destructive-proposal:\s*#\d+/i

function stripSqlComments(sql) {
  return sql.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/--[^\n]*/g, ' ').replace(/'(?:[^']|'')*'/g, "''")
}

export function classifyStatement(statement) {
  const s = statement.trim()
  if (!s) return []
  const kinds = DESTRUCTIVE_PATTERNS.filter(({ re }) => re.test(s)).map(({ kind }) => kind)
  if (/\bdelete\s+from\b/i.test(s) && !/\bwhere\b/i.test(s)) kinds.push('DELETE without WHERE')
  return kinds
}

// Parses `git diff --unified=0` output. Returns findings for guarded files whose
// added lines introduce a destructive statement without the marker.
export function findDestructiveSql(diffText) {
  const files = new Map()
  let current = null
  for (const line of String(diffText ?? '').split(/\r?\n/)) {
    const header = line.match(/^diff --git a\/.+ b\/(.+)$/)
    if (header) { current = header[1]; files.set(current, []); continue }
    if (current === null || line.startsWith('+++')) continue
    if (line.startsWith('+')) files.get(current).push(line.slice(1))
  }
  const findings = []
  for (const [file, added] of files) {
    if (!isGuardedSqlPath(file) || added.length === 0) continue
    const raw = added.join('\n')
    if (MARKER.test(raw)) continue
    const kinds = new Set()
    for (const statement of stripSqlComments(raw).split(';')) for (const k of classifyStatement(statement)) kinds.add(k)
    if (kinds.size) findings.push({ file, kinds: [...kinds] })
  }
  return findings
}
