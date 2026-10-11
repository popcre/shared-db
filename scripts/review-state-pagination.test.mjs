import test from 'node:test'
import assert from 'node:assert/strict'
import { completeReviewStateConnections, reviewStateEntry } from './lib/lanes/github-wire.mjs'
import { reviewStateConnectionPageQuery, reviewStateGraphqlFields } from './lib/lanes/review-assignment.mjs'

const conn=(nodes,hasNextPage=false,endCursor=null)=>({pageInfo:{hasNextPage,endCursor},nodes})
const pr=(over={})=>({state:'OPEN',merged:false,mergeCommit:null,headRefOid:'a'.repeat(40),comments:conn([{body:'c1',authorAssociation:'OWNER'}]),reviews:conn([]),...over})
const issue=(over={})=>({state:'OPEN',comments:conn([{body:'i1',authorAssociation:'OWNER'}]),...over})

test('batched fields request endCursor for every evidence connection',()=>{
  const fields=reviewStateGraphqlFields({issue:3536,pr:4171},0)
  assert.equal((fields.match(/pageInfo\{hasNextPage endCursor\}/g)??[]).length,3)
})

test('an issue with more than 100 comments is completed, not refused (#3536)',()=>{
  const calls=[]
  const fetchPage=(kind,number,after)=>{calls.push([kind,number,after]);return after==='c1'?conn([{body:'i101',authorAssociation:'OWNER'}],true,'c2'):conn([{body:'i102',authorAssociation:'MEMBER'}],false,'c3')}
  const full=completeReviewStateConnections(pr(),issue({comments:conn([{body:'i1',authorAssociation:'OWNER'}],true,'c1')}),{prNumber:4171,issueNumber:3536},fetchPage)
  assert.deepEqual(calls,[['issue.comments',3536,'c1'],['issue.comments',3536,'c2']])
  assert.deepEqual(full.issue.comments.nodes.map((n)=>n.body),['i1','i101','i102'])
  assert.equal(full.issue.comments.pageInfo.hasNextPage,false)
  const entry=reviewStateEntry(full.pr,full.issue)
  assert.deepEqual(entry.evidence.map((e)=>e.body),['i1','i101','i102','c1'])
})

test('reviewStateEntry completes a paginated issue itself when the batch carried numbers',()=>{
  const calls=[]
  const entry=reviewStateEntry(pr({number:4171}),issue({number:3536,comments:conn([{body:'i1',authorAssociation:'OWNER'}],true,'c1')}),(kind,number,after)=>{calls.push([kind,number,after]);return conn([{body:'i101',authorAssociation:'OWNER'}])})
  assert.deepEqual(calls,[['issue.comments',3536,'c1']])
  assert.deepEqual(entry.evidence.map((e)=>e.body),['i1','i101','c1'])
})

test('batched fields request pr and issue numbers',()=>{
  const fields=reviewStateGraphqlFields({issue:3536,pr:4171},0)
  assert.match(fields,/pullRequest\(number:4171\)\{number state/)
  assert.match(fields,/issue\(number:3536\)\{number state/)
})

test('complete connections make no follow-up request',()=>{
  const full=completeReviewStateConnections(pr(),issue(),{prNumber:1,issueNumber:2},()=>{throw new Error('must not fetch')})
  assert.equal(full.issue.comments.nodes.length,1)
})

test('pagination still fails closed on a missing cursor, a bad page, or too many pages',()=>{
  assert.throws(()=>completeReviewStateConnections(pr({reviews:conn([],true,null)}),issue(),{prNumber:1,issueNumber:2},()=>conn([])),/without a cursor/)
  assert.throws(()=>completeReviewStateConnections(pr({comments:conn([],true,'x')}),issue(),{prNumber:1,issueNumber:2},()=>({nodes:null})),/unreadable/)
  assert.throws(()=>completeReviewStateConnections(pr(),issue({comments:conn([],true,'x')}),{prNumber:1,issueNumber:2},()=>conn([],true,'y'),3),/exceeds 3 extra pages/)
  assert.throws(()=>reviewStateEntry(pr(),issue({comments:conn([],true,'x')})),/incomplete or paginated/)
  // Numbers present: a failing follow-up still refuses.
  assert.throws(()=>reviewStateEntry(pr({number:4171}),issue({number:3536,comments:conn([],true,'x')}),()=>{throw new Error('wire down')}),/wire down/)
})

test('follow-up page queries select the same node fields',()=>{
  assert.match(reviewStateConnectionPageQuery('issue.comments'),/issue\(number:\$number\)\{comments\(first:100,after:\$after\).*nodes\{body authorAssociation\}/)
  assert.match(reviewStateConnectionPageQuery('pr.reviews'),/pullRequest\(number:\$number\)\{reviews\(first:100,after:\$after\).*nodes\{body state authorAssociation commit\{oid\}\}/)
  assert.throws(()=>reviewStateConnectionPageQuery('nope'),/unknown/)
})
