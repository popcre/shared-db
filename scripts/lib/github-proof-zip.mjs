import { execFileSync } from 'node:child_process'

// GitHub Actions artifact downloads are ZIP files. Read named files without
// extracting paths to disk; the archive's bytes never become filesystem paths.
const PYTHON_READ_ZIP = String.raw`
import base64, io, json, stat, sys, zipfile

expected = json.loads(sys.argv[1])
allow_unrelated = sys.argv[2] == 'allow-unrelated'
if not isinstance(expected, list) or not expected or len(expected) != len(set(expected)):
    raise ValueError('expected proof files are invalid')
if any(not isinstance(name, str) or not name or '/' in name or '\\' in name or name in ('.', '..') for name in expected):
    raise ValueError('expected proof file path is invalid')
archive_bytes = sys.stdin.buffer.read(20 * 1024 * 1024 + 1)
if len(archive_bytes) > 20 * 1024 * 1024:
    raise ValueError('proof artifact ZIP exceeds 20 MiB')
with zipfile.ZipFile(io.BytesIO(archive_bytes)) as archive:
    entries = archive.infolist()
    if not entries or len(entries) > 64 or (not allow_unrelated and (len(entries) != len(expected) or set(entry.filename for entry in entries) != set(expected))):
        raise ValueError('proof artifact must contain exactly the expected files')
    result = {}
    total = 0
    seen_paths = set()
    for entry in entries:
        if (entry.filename.startswith('/') or '\\' in entry.filename or
            any(part in ('', '.', '..') for part in entry.filename.split('/'))):
            raise ValueError('proof artifact contains an unsafe path')
        if entry.filename in seen_paths:
            raise ValueError('proof artifact contains a duplicate path')
        seen_paths.add(entry.filename)
        mode = (entry.external_attr >> 16) & 0xffff
        if entry.is_dir() or stat.S_IFMT(mode) not in (0, stat.S_IFREG) or entry.flag_bits & 1:
            raise ValueError('proof artifact contains a directory, link, or encrypted file')
        if entry.file_size > 4 * 1024 * 1024 or total + entry.file_size > 16 * 1024 * 1024:
            raise ValueError('proof artifact expands beyond allowed size')
        matches = [name for name in expected if entry.filename == name or (allow_unrelated and entry.filename.endswith('/' + name))]
        if len(matches) > 1 or (not allow_unrelated and not matches):
            raise ValueError('proof artifact file selection is ambiguous')
        if matches and matches[0] in result:
            raise ValueError('proof artifact duplicates an expected file')
        with archive.open(entry) as handle:
            data = handle.read(4 * 1024 * 1024 + 1)
            if len(data) != entry.file_size or len(data) > 4 * 1024 * 1024:
                raise ValueError('proof artifact file size is invalid')
        total += len(data)
        if matches:
            result[matches[0]] = base64.b64encode(data).decode('ascii')
    if set(result) != set(expected):
        raise ValueError('proof artifact is missing an expected file')
print(json.dumps(result, separators=(',', ':')))
`

export function runPythonWithFallback(args, options, executor = execFileSync) {
  try {
    return executor('python3', args, options)
  } catch (error) {
    // Python's Windows installer may expose only `python`. Retry an absent
    // executable, never a failed or refused ZIP inspection.
    if (error?.code !== 'ENOENT') throw error
    return executor('python', args, options)
  }
}

export function readExactProofZip(bytes, expectedFiles, { allowUnrelatedFiles = false } = {}) {
  if (!Buffer.isBuffer(bytes) || bytes.length > 20 * 1024 * 1024) throw new Error('proof artifact ZIP exceeds 20 MiB or is unreadable')
  if (!Array.isArray(expectedFiles) || !expectedFiles.length || new Set(expectedFiles).size !== expectedFiles.length ||
      expectedFiles.some((name) => typeof name !== 'string' || !name || name.includes('/') || name.includes('\\') || name === '.' || name === '..')) {
    throw new Error('expected proof files are invalid')
  }
  let encoded
  try {
    encoded = runPythonWithFallback(['-c', PYTHON_READ_ZIP, JSON.stringify(expectedFiles), allowUnrelatedFiles ? 'allow-unrelated' : 'exact'], {
      input: bytes, encoding: 'utf8', maxBuffer: 24 * 1024 * 1024,
      stdio: ['pipe', 'pipe', 'pipe'],
    })
  } catch (error) {
    const reason = String(error?.stderr ?? error?.message ?? 'invalid ZIP').trim().split('\n').at(-1)
    throw new Error(`proof artifact ZIP refused: ${reason}`)
  }
  const files = JSON.parse(encoded)
  return new Map(expectedFiles.map((name) => [name, Buffer.from(files[name], 'base64').toString('utf8')]))
}
