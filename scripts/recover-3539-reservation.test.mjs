import assert from 'node:assert/strict'
import test from 'node:test'
import { claimBody, MUTEX_REF } from './manage-migration-author-lanes.mjs'
import { recover3539Reservation, TARGET } from './recover-3539-reservation.mjs'

const HEAD='f'.repeat(40),OLD_SHA='e'.repeat(40),NOW=new Date('2026-09-28T00:00:00Z')
const ARGS={headSha:HEAD,targetWorktree:'/tmp/exact-pr-head'}
function fixture(){
  const refs=new Map([[`refs/db-claims/${TARGET.oldVersion}`,OLD_SHA]]),commits=new Map(),objects=['function api.db_data_admin_scraped_source_inventory']
  const claim={number:3546,state:'open',title:'CLAIM: #3539 Pixar under Disney',body:claimBody({version:TARGET.newVersion,objects,owner:TARGET.owner,branch:TARGET.branch,worktree:TARGET.worktree,expiresAt:new Date('2026-09-26T05:48:20.047Z')})}
  const workIssue={number:3539,state:'open',body:'```db-work-scope\nstatus: ready\nwork_type: structural\nroute: shared-db-orchestrator\nservice_class: standard-application\nchange_type: migration\npriority: 5\nobjects:\n  - function api.db_data_admin_scraped_source_inventory\n```'}
  let sequence=0
  const io={refs,claim,workIssue,
    makeOwnerCommit(message){const sha=(++sequence).toString(16).padStart(40,'0');commits.set(sha,{message});return sha},getCommit:sha=>commits.get(sha),
    readRef:ref=>refs.get(ref)??null,listRefs:prefix=>[...refs].filter(([ref])=>ref.startsWith(prefix)).map(([ref,sha])=>({ref,sha})),createRef(ref,sha){if(refs.has(ref))return false;refs.set(ref,sha);return true},deleteRef:ref=>refs.delete(ref),
    getIssue:n=>structuredClone(Number(n)===3546?claim:workIssue),openClaims:()=>[structuredClone(claim)],
    getPr:()=>({state:'open',head:{sha:HEAD,ref:TARGET.branch}}),getPrFiles:()=>[{status:'added',filename:`supabase/migrations/${TARGET.newVersion}_licensor.sql`}],
    localClean:()=>true,localHead:()=>HEAD,mainSha:()=> 'main',treeFiles:()=>['supabase/migrations/20260925193145_prior.sql'],
    prSources:()=>[{label:'PR #3557',versions:[TARGET.newVersion],objects}],
  }
  return io
}
test('creates exact permanent protection, preserves old ref, and is idempotent',()=>{
  const io=fixture(),first=recover3539Reservation(ARGS,NOW,io)
  assert.equal(first.idempotent,false);assert.equal(io.readRef(`refs/db-claims/${TARGET.oldVersion}`),OLD_SHA)
  assert.equal(io.readRef(first.reservation),first.sha);assert.equal(io.readRef(first.evidence),first.sha)
  assert.equal(recover3539Reservation(ARGS,NOW,io).idempotent,true)
  assert.equal(io.readRef(MUTEX_REF),null)
})
test('refuses changed head, dirty checkout, higher main version, competing PR, and foreign ref',()=>{
  const cases=[
    [io=>{io.getPr=()=>({state:'open',head:{sha:'a'.repeat(40),ref:TARGET.branch}})},/exact head/],
    [io=>{io.localClean=()=>false},/dirty/],
    [io=>{io.treeFiles=()=>['supabase/migrations/20260926000000_later.sql']},/later than/],
    [io=>{io.prSources=()=>[{label:'PR #3557',versions:[TARGET.newVersion],objects:['function api.db_data_admin_scraped_source_inventory']},{label:'PR #9999',versions:[TARGET.newVersion],objects:[]}]},/another PR/],
    [io=>{io.prSources=()=>[{label:'PR #3557',versions:[TARGET.newVersion],objects:['function public.foreign']}]},/outside the exact claim/],
    [io=>{io.refs.set(`refs/db-claims/${TARGET.newVersion}`,'a'.repeat(40))},/unreadable/],
  ]
  for(const [mutate,reason] of cases){const io=fixture();mutate(io);assert.throws(()=>recover3539Reservation(ARGS,NOW,io),reason);assert.equal(io.readRef(`refs/db-claims/${TARGET.oldVersion}`),OLD_SHA)}
})
test('completes a matching durable reservation after an interrupted evidence write',()=>{
  const io=fixture(),create=io.createRef
  io.createRef=(ref,sha)=>{if(ref.startsWith('refs/db-claim-supersessions/'))throw new Error('write interrupted');return create(ref,sha)}
  assert.throws(()=>recover3539Reservation(ARGS,NOW,io),/interrupted/)
  const reserved=io.readRef(`refs/db-claims/${TARGET.newVersion}`)
  assert.ok(reserved);io.createRef=create
  const result=recover3539Reservation(ARGS,NOW,io)
  assert.equal(result.resumed,true);assert.equal(io.readRef(result.evidence),reserved)
})
