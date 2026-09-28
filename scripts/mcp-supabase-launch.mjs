#!/usr/bin/env node
// Cross-platform launcher for the project Supabase MCP server (.mcp.json).
// Issue #3659. Routes through the machine's ai-devops secret launcher, which
// injects SUPABASE_ACCESS_TOKEN from 1Password; no secret lives in this repo.
//   Windows: cmd /c %USERPROFILE%\.config\ai-devops\mcp-launch.cmd cmd /c npx ...
//   Linux/macOS: ~/.config/ai-devops/mcp-launch.sh npx ...
import { spawn } from 'node:child_process'
import { homedir } from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

export const SERVER_ARGS = [
  '-y',
  '@supabase/mcp-server-supabase@0.11.0',
  '--read-only',
  '--project-ref',
  'qsllyeztdwjgirsysgai',
]

// Path joining must follow the *target* platform, not the host running tests,
// so a Windows host can still assert the Linux plan and vice versa.
export function launchPlan(platform = process.platform, home = homedir()) {
  const join = platform === 'win32' ? path.win32.join : path.posix.join
  const dir = join(home, '.config', 'ai-devops')
  if (platform === 'win32') {
    return {
      command: 'cmd',
      args: ['/c', join(dir, 'mcp-launch.cmd'), 'cmd', '/c', 'npx', ...SERVER_ARGS],
    }
  }
  return { command: join(dir, 'mcp-launch.sh'), args: ['npx', ...SERVER_ARGS] }
}

const isMain =
  Boolean(process.argv[1]) &&
  fileURLToPath(import.meta.url) === path.resolve(process.argv[1])

if (isMain) {
  const { command, args } = launchPlan()
  const child = spawn(command, args, { stdio: 'inherit', windowsHide: true })
  child.on('error', (err) => {
    console.error(`mcp-supabase-launch: cannot start ${command}: ${err.message}`)
    process.exit(127)
  })
  child.on('exit', (code, signal) => process.exit(signal ? 1 : (code ?? 1)))
  for (const s of ['SIGINT', 'SIGTERM']) process.on(s, () => child.kill(s))
}
