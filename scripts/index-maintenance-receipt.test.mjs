import test from 'node:test'
import assert from 'node:assert/strict'
import {createReceipt,readReceipt,validateRef} from './index-maintenance-receipt.mjs'
const ref='refs/db-index-maintenance/synthetic-operation/preview/started'
function io(){const refs=new Map(),commits=new Map();let n=0;return {refs,commits,readRef:r=>refs.get(r)??null,getCommit:s=>({message:commits.get(s)}),makeOwnerCommit:m=>{const s=String(++n);commits.set(s,m);return s},createRef:(r,s)=>{if(refs.has(r))return false;refs.set(r,s);return true}}}
test('receipt refs reject other authority namespaces and injection',()=>{for(const r of ['refs/heads/main',ref+';drop','refs/db-index-maintenance/../preview/started',ref.replace('/preview/','/unknown/')])assert.throws(()=>validateRef(r))})
test('canonical immutable create reads back exact content',()=>{const state=io(),record={phase:'started',source_sha:'a'.repeat(40)};assert.equal(readReceipt(ref,state),null);assert.deepEqual(createReceipt(ref,record,state),record);assert.deepEqual(readReceipt(ref,state),record)})
test('same receipt is idempotent and conflicting receipt never updates',()=>{const state=io();createReceipt(ref,{a:1},state);const before=state.refs.get(ref);assert.deepEqual(createReceipt(ref,{a:1},state),{a:1});assert.throws(()=>createReceipt(ref,{a:2},state));assert.equal(state.refs.get(ref),before)})
test('unrecognized commit payload and excessive records refuse',()=>{const state=io();state.refs.set(ref,'bad');state.commits.set('bad','unrelated');assert.throws(()=>readReceipt(ref,state));assert.throws(()=>createReceipt(ref,{body:'x'.repeat(33000)},io()))})

import {verifyMaintenanceClaim} from './index-maintenance-receipt.mjs'
import {EXCLUSIVE_REFS} from './lib/lanes/queue-routing.mjs'
import {pairKindForExclusiveKind} from './lib/lanes/exclusive-policy.mjs'
const objects=['table public.style_guide_search_documents','index public.original','index public.replacement','index public.retired']
const request={claim_issue:99,work_issue:5616,objects}
function claim(number=99,workIssue=5616,writes=objects,expiry='2099-01-01T00:00:00Z'){
 return {number,title:`CLAIM: #${workIssue} index maintenance`,body:['```db-claim','version: 29990101000000','objects:',...writes.map(w=>'  - '+w),'```','','```db-author-lease','owner: synthetic-test','branch: codex/synthetic','worktree: /tmp/synthetic','expires_at: '+expiry,'```'].join('\n')}
}
test('maintenance shares existing preview exclusive ref and compatibility role',()=>{assert.equal(EXCLUSIVE_REFS['preview-maintenance'],EXCLUSIVE_REFS.preview);assert.equal(pairKindForExclusiveKind('preview-maintenance'),'preview')})
test('exact native live claim admits all fixed writes',()=>assert.deepEqual(verifyMaintenanceClaim(request,{openClaims:()=>[claim()]}),{admitted:true,claim_issue:99,work_issue:5616}))
test('missing incomplete or differently owned work claim refuses',()=>{
 for(const claims of [[],[claim(100)],[claim(99,777)],[claim(99,5616,objects.slice(1))]])assert.throws(()=>verifyMaintenanceClaim(request,{openClaims:()=>claims}))
})
test('expired foreign claim still protects its colliding object',()=>assert.throws(()=>verifyMaintenanceClaim(request,{openClaims:()=>[claim(),claim(100,777,[objects[0]],'2020-01-01T00:00:00Z')]})))

test('retired author lease clocks do not block an exact open object claim',()=>{assert.equal(verifyMaintenanceClaim(request,{openClaims:()=>[claim(99,5616,objects,'2020-01-01T00:00:00Z')]}).admitted,true);const current=claim();current.body=current.body.split('```db-author-lease')[0].trim();assert.equal(verifyMaintenanceClaim(request,{openClaims:()=>[current]}).admitted,true)})

import {maintenanceExclusive} from './index-maintenance-receipt.mjs'
function lockIo(){
 const state=io();state.maintenanceSourceExecute=(_p,_a,opts)=>{const r=JSON.parse(opts.input);return JSON.stringify({source_sha:r.head_sha,current_main_sha:state.mainSha(),source_pr:r.source_pr,run_id:r.run_id})};state.deleteRef=ref=>state.refs.delete(ref);state.readCommitMessage=sha=>state.commits.get(sha);state.mainSha=()=> 'a'.repeat(40);state.getPr=()=>({merged:true,merge_commit_sha:'a'.repeat(40)});state.compareCommits=()=>({status:'identical',behind_by:0});state.openClaims=()=>[claim()];return state
}
test('actual native exclusive manager acquires fences and releases the existing preview ref',()=>{
 const state=lockIo(),r={target:'preview',run_id:123,source_pr:1,head_sha:'a'.repeat(40),claim:request}
 r.lease=maintenanceExclusive('acquire',r,state)
 assert.equal(state.refs.get(EXCLUSIVE_REFS.preview),r.lease.ownerSha)
 assert.equal(maintenanceExclusive('assert',r,state).holderId,r.lease.holderId)
 maintenanceExclusive('release',r,state)
 assert.equal(state.refs.has(EXCLUSIVE_REFS.preview),false)
})
test('actual native production manager refuses overlapping merge and preserves that owner',()=>{
 const state=lockIo();state.refs.set(EXCLUSIVE_REFS.merge,'foreign-merge')
 const r={target:'production',run_id:123,source_pr:1,head_sha:'a'.repeat(40),claim:request}
 assert.throws(()=>maintenanceExclusive('acquire',r,state),/guarded merge/)
 assert.equal(state.refs.get(EXCLUSIVE_REFS.merge),'foreign-merge')
})


import {execFileSync} from 'node:child_process'
import {createHash} from 'node:crypto'
import {fileURLToPath} from 'node:url'
const nativeOp='sg-hnsw-rebuild-5616-v1'
const nativeSuffix=createHash('sha256').update(nativeOp).digest('hex').slice(0,12)
const nativeObjects=['table public.style_guide_search_documents','index public.idx_sg_search_documents_embedding_hnsw',`index public.sg_hnsw_${nativeSuffix}_new`,`index public.sg_hnsw_${nativeSuffix}_retired`]
function actualGateIo(caseName='unrelated'){
 const state=lockIo();state.testCase=caseName;state.mainSha=()=> 'd'.repeat(40)
 state.getPr=()=>({merged:true,merge_commit_sha:'c'.repeat(40)})
 state.compareCommits=()=>({status:'ahead',behind_by:0})
 state.openClaims=()=>[claim(99,5616,nativeObjects)]
 state.maintenanceSourceExecute=(_program,_args,opts)=>execFileSync('python3',[fileURLToPath(new URL('./test_index_maintenance_workflow_gate.py',import.meta.url)),'--native-fixture'],{...opts,input:JSON.stringify({...JSON.parse(opts.input),_test_case:state.testCase}),stdio:['pipe','pipe','pipe']})
 return state
}
function actualRequest(target){return {target,run_id:123,source_pr:1,head_sha:'b'.repeat(40),dispatch_ref:`refs/db-index-maintenance-operations/${nativeOp}/${target}/${'b'.repeat(40)}`,claim:{claim_issue:99,work_issue:5616,objects:nativeObjects}}}
test('actual native preview admission invokes full Python bot/source/claim/target gate; irrelevant HTS ancestor succeeds',()=>{
 const state=actualGateIo(),r=actualRequest('preview')
 r.lease=maintenanceExclusive('acquire',r,state)
 assert.equal(state.refs.get(EXCLUSIVE_REFS.preview),r.lease.ownerSha)
 assert.equal(maintenanceExclusive('assert',r,state).holderId,r.lease.holderId)
 maintenanceExclusive('release',r,state);assert.equal(state.refs.has(EXCLUSIVE_REFS.preview),false)
})
test('actual native preview refuses changed guard/current policy/new dependency and nonancestor without creating lease',()=>{
 for(const kind of ['guard','policy','dependency','atomic','forcepush']){
  const state=actualGateIo(kind),r=actualRequest('preview')
  assert.throws(()=>maintenanceExclusive('acquire',r,state))
  assert.equal(state.refs.has(EXCLUSIVE_REFS.preview),false)
 }
})
test('actual native gate rejects forged proof booleans and changed source/run/PR bindings',()=>{
 for(const value of [true,{source_sha:'b'.repeat(40),current_main_sha:'d'.repeat(40),source_pr:99,run_id:123},{source_sha:'b'.repeat(40),current_main_sha:'d'.repeat(40),source_pr:1,run_id:999}]){
  const state=actualGateIo();state.maintenanceSourceExecute=()=>JSON.stringify(value)
  assert.throws(()=>maintenanceExclusive('acquire',actualRequest('preview'),state))
  assert.equal(state.refs.has(EXCLUSIVE_REFS.preview),false)
 }
})

test('actual native production admission re-derives full authority; normal production-prefix policy unchanged',()=>{
 const state=actualGateIo(),r=actualRequest('production')
 r.lease=maintenanceExclusive('acquire',r,state)
 assert.equal(state.refs.get(EXCLUSIVE_REFS.production),r.lease.ownerSha)
 assert.equal(maintenanceExclusive('assert',r,state).holderId,r.lease.holderId)
 state.testCase='guard'
 assert.throws(()=>maintenanceExclusive('assert',r,state))
 assert.equal(state.refs.get(EXCLUSIVE_REFS.production),r.lease.ownerSha)
 maintenanceExclusive('release',r,state)
 assert.equal(state.refs.has(EXCLUSIVE_REFS.production),false)
})
