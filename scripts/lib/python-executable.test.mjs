import assert from 'node:assert/strict'
import test from 'node:test'
import { pythonExecutable } from './python-executable.mjs'

test('#3629 chooses Python 3 on Linux, preserves Windows, and honors explicit override',()=>{
  assert.equal(pythonExecutable({platform:'linux',env:{}}),'python3')
  assert.equal(pythonExecutable({platform:'win32',env:{}}),'python')
  assert.equal(pythonExecutable({platform:'linux',env:{PYTHON:'/opt/project/python'}}),'/opt/project/python')
  assert.equal(pythonExecutable({platform:'linux',env:{PYTHON:'  '}}),'python3')
})
