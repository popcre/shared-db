import test from 'node:test'
import assert from 'node:assert/strict'
import { projectReviewPr, reviewStateGraphqlFields } from './lib/lanes/review-assignment.mjs'
import { isReviewAssignmentLive } from './lib/lanes/review-approval.mjs'
const head='a'.repeat(40),mergedAt='2026-10-02T17:48:00Z'
const assignment={issue:3891,pr:3893,headSha:head,slot:4}
function live(pr,binding=true){
  const states=new Map([['3891:3893',{pr}]])
  return isReviewAssignmentLive(assignment,states,{listRefs:()=>[],mergedPrReviewTarget:(p,i)=>binding&&p===3893&&i===3891})
}
test('batched lease query requests actual merge time used by merged-target authority',()=>{
  assert.match(reviewStateGraphqlFields(assignment,0),/\bmergedAt\b/)
})
test('real merged GraphQL projection retains authority metadata and restores pending slot',()=>{
  const pr=projectReviewPr({state:'MERGED',merged:true,mergedAt,mergeCommit:{oid:'b'.repeat(40)},headRefOid:head})
  assert.equal(pr.merged_at,mergedAt)
  assert.equal(live(pr),true)
  assert.equal(live(pr,false),false)
})
test('merged boolean alone cannot manufacture a merged timestamp or revival authority',()=>{
  const pr=projectReviewPr({state:'CLOSED',merged:true,mergeCommit:{oid:'b'.repeat(40)},headRefOid:head})
  assert.equal(pr.merged_at,null)
  assert.equal(live(pr),false)
})
test('unmerged and moved-head projections stay ineligible; open review stays live',()=>{
  assert.equal(live(projectReviewPr({state:'CLOSED',merged:false,mergedAt:null,headRefOid:head})),false)
  assert.equal(live(projectReviewPr({state:'MERGED',merged:true,mergedAt,headRefOid:'c'.repeat(40)})),false)
  assert.equal(live(projectReviewPr({state:'OPEN',merged:false,mergedAt:null,headRefOid:head}),false),true)
})
