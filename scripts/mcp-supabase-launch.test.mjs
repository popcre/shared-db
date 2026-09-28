import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { launchPlan, SERVER_ARGS } from './mcp-supabase-launch.mjs'

test('windows keeps the cmd launcher route', () => {
  const plan = launchPlan('win32', 'C:\\Users\\x')
  const expectedLauncher = path.win32.join('C:\\Users\\x', '.config', 'ai-devops', 'mcp-launch.cmd')
  assert.equal(plan.command, 'cmd')
  assert.equal(plan.args[0], '/c')
  assert.equal(plan.args[1], expectedLauncher)
  assert.deepEqual(plan.args.slice(2), ['cmd', '/c', 'npx', ...SERVER_ARGS])
})

test('linux uses the shell launcher and never cmd', () => {
  const plan = launchPlan('linux', '/home/x')
  const expectedLauncher = path.posix.join('/home/x', '.config', 'ai-devops', 'mcp-launch.sh')
  assert.equal(plan.command, expectedLauncher)
  assert.deepEqual(plan.args, ['npx', ...SERVER_ARGS])
  assert.ok(!plan.command.includes('cmd'))
})

test('darwin uses the shell launcher too', () => {
  const plan = launchPlan('darwin', '/Users/x')
  assert.equal(plan.command, path.posix.join('/Users/x', '.config', 'ai-devops', 'mcp-launch.sh'))
  assert.deepEqual(plan.args, ['npx', ...SERVER_ARGS])
})

test('server stays read-only at the pinned version and project ref', () => {
  assert.ok(SERVER_ARGS.includes('--read-only'))
  assert.ok(SERVER_ARGS.includes('@supabase/mcp-server-supabase@0.11.0'))
  const refAt = SERVER_ARGS.indexOf('--project-ref')
  assert.ok(refAt >= 0)
  assert.equal(SERVER_ARGS[refAt + 1], 'qsllyeztdwjgirsysgai')
})

test('.mcp.json launches through node, not cmd, and holds no secret', () => {
  const cfg = JSON.parse(readFileSync(new URL('../.mcp.json', import.meta.url), 'utf8'))
  const s = cfg.mcpServers.supabase
  assert.equal(s.command, 'node')
  assert.deepEqual(s.args, ['scripts/mcp-supabase-launch.mjs'])
  assert.equal(s.env, undefined)
  const raw = JSON.stringify(cfg)
  assert.ok(!/token|password|secret|SUPABASE_ACCESS/i.test(raw))
})
