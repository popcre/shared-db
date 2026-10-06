import test from 'node:test'
import assert from 'node:assert/strict'
import { isReviewAssignmentLive, assertReviewLeaseStillStale } from './lib/lanes/review-approval.mjs'
import { findBusyReviewers } from './lib/lanes/review-leases.mjs'
import { reviewLeaseRefForAssignment } from './lib/lanes/review-records.mjs'
import { verdictRef } from './lib/review-verdict-artifact.mjs'
const head='a'.repeat(40),assignment={issue:3891,pr:3893,headSha:head,slot:4,sequence:4978,reviewer:'grok-4.6'}
function fixture({state='closed',merged=true,binding=true,slot=4,sha=head,verdictSlot=null}={}){
  const record={...assignment,slot},pr={state,head:{sha},merged_at:merged?'2026-10-02T17:48:00Z':null}
  const states=new Map([['3891:3893',{pr}]])
  const ref=reviewLeaseRefForAssignment(record,true)
  const io={requiresExactReviewHeadSha:true,getPr:()=>pr,mergedPrReviewTarget:(p,i)=>binding&&p===3893&&i===3891,
    readRef:()=> 'b'.repeat(40),readReviewStates:()=>states,
    readActiveReviewLeases:()=>new Map([[ref,{sha:'c'.repeat(40),commit:{message:`db-coordination reviewer-cursor sequence=4978 reviewer=grok-4.6 issue=3891 pr=3893 head=${head}${slot===1?'':` slot=${slot}`}`}}]]),
    listRefs:()=>verdictSlot===null?[]:[{ref:verdictRef({...assignment,slot:verdictSlot}),sha:'d'.repeat(40)}]}
  return {record,states,io}
}
test('verified post-merge replacement can restore its exact review reservation',()=>{
  const {record,states,io}=fixture()
  assert.equal(isReviewAssignmentLive(record,states,io),true)
})
test('unbound lease scanning protects unfinished post-merge review from reclamation',()=>{
  const {record,states,io}=fixture({binding:false})
  assert.equal(isReviewAssignmentLive(record,states,io),false)
  const busy=findBusyReviewers(io)
  assert.equal(busy.has('grok-4.6'),true)
  assert.deepEqual(busy.stale,[])
  assert.throws(()=>assertReviewLeaseStillStale({assignment:record},states,io),/became live/)
})
test('closed unmerged, changed head, missing authority and merge-review slot stay ineligible',()=>{
  for(const config of [{merged:false},{sha:'e'.repeat(40)},{binding:false},{slot:1}]){
    const {record,states,io}=fixture(config)
    assert.equal(isReviewAssignmentLive(record,states,io),false)
  }
})
test('own durable verdict releases the lease; a sibling verdict does not',()=>{
  for(const verdictSlot of [3,4]){
    const {record,states,io}=fixture({verdictSlot})
    assert.equal(isReviewAssignmentLive(record,states,io),verdictSlot!==4)
    const busy=findBusyReviewers(io)
    assert.equal(busy.has('grok-4.6'),verdictSlot!==4)
    assert.equal(busy.stale.length,verdictSlot===4?1:0)
  }
})
test('ordinary open review remains live without merged-issue authority',()=>{
  const {record,states,io}=fixture({state:'open',merged:false,binding:false,slot:1})
  assert.equal(isReviewAssignmentLive(record,states,io),true)
  assert.equal(findBusyReviewers(io).has('grok-4.6'),true)
})
test('missing merged binding capability cannot revive a reservation',()=>{
  const {record,states,io}=fixture()
  delete io.mergedPrReviewTarget
  assert.equal(isReviewAssignmentLive(record,states,io),false)
})
test('closed unmerged, changed head and merged slot 1 can be reclaimed',()=>{
  for(const config of [{merged:false},{sha:'e'.repeat(40)},{slot:1}]){
    const {record,states,io}=fixture(config)
    assert.equal(findBusyReviewers(io).stale.length,1)
    assert.doesNotThrow(()=>assertReviewLeaseStillStale({assignment:record},states,io))
  }
})
