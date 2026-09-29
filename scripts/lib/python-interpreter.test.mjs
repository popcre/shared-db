import test from 'node:test'
import assert from 'node:assert/strict'
import { pythonInterpreter } from './python-interpreter.mjs'

test('Linux uses python3, never bare python', () => {
  assert.equal(pythonInterpreter({ env: {}, platform: 'linux' }), 'python3')
  assert.notEqual(pythonInterpreter({ env: {}, platform: 'linux' }), 'python')
})
test('Windows uses python', () => {
  assert.equal(pythonInterpreter({ env: {}, platform: 'win32' }), 'python')
})
test('an explicit PYTHON override wins on every platform', () => {
  for (const platform of ['linux', 'win32', 'darwin']) assert.equal(pythonInterpreter({ env: { PYTHON: '/opt/py/bin/python3.12' }, platform }), '/opt/py/bin/python3.12')
})
test('an empty PYTHON does not select an empty executable', () => {
  assert.equal(pythonInterpreter({ env: { PYTHON: '' }, platform: 'linux' }), 'python3')
})
