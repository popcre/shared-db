import assert from 'node:assert/strict'
import test from 'node:test'
import { fileURLToPath } from 'node:url'
import { assertReviewFindingHoldClear, LaneError, REPO as THIS_REPO } from './manage-migration-author-lanes.mjs'


test('review finding hold invocation is portable and anchored independently of cwd',()=>{
  for(const platform of ['win32','linux']){
    let invocation
    assertReviewFindingHoldClear(5131,{platform,run:(...args)=>{invocation=args}})
    assert.equal(invocation[0],platform==='win32'?'python':'python3')
    assert.equal(invocation[1][0],fileURLToPath(new URL('./review_finding_hold.py',import.meta.url)))
    assert.deepEqual(invocation[1].slice(1),['--pr','5131','--repo',THIS_REPO])
    assert.equal(invocation[2].timeout,180000)
    assert.equal(invocation[2].maxBuffer,1024*1024)
  }
})

test('review finding hold preserves blocking identity and distinguishes operational failures',()=>{
  const held='HELD: review-finding #5134 references PR #5131: https://github.com/popcre/shared-db/issues/5134'
  const failures=[
    {status:3,stdout:held,stderr:'hold details'},
    {status:2,stderr:'could not query issues'},
    {status:2,stderr:'usage: invalid arguments'},
    {code:'ENOENT'},
    {code:'ETIMEDOUT',signal:'SIGTERM'},
    {code:'ENOBUFS',stdout:'partial output'},
  ]
  for(const details of failures){
    const error=Object.assign(new Error('execution failed'),details)
    assert.throws(()=>assertReviewFindingHoldClear(5131,{run:()=>{throw error}}),(caught)=>{
      assert.ok(caught instanceof LaneError)
      assert.match(caught.message,details.status===3?/blocking review-finding/:/hold query failed/)
      for(const value of [details.stdout,details.stderr,details.code,details.signal].filter(Boolean))assert.ok(caught.message.includes(value))
      if(details.status!==undefined&&details.status!==3)assert.ok(caught.message.includes(`status=${details.status}`))
      return true
    })
  }
})
