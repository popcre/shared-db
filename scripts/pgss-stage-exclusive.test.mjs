import test from 'node:test'
import assert from 'node:assert/strict'
import {qualify,checkLease} from './pgss-stage-exclusive.mjs'
const env={GITHUB_REPOSITORY:'popcre/shared-db',GITHUB_REF:'refs/heads/main',GITHUB_EVENT_NAME:'workflow_dispatch',
 GITHUB_WORKFLOW_REF:'popcre/shared-db/.github/workflows/stage-pgss-capacity.yml@refs/heads/main',
 GITHUB_SHA:'a'.repeat(40),EXPECTED_HEAD:'a'.repeat(40),WORK_ISSUE:'5609',GITHUB_RUN_ID:'100',GITHUB_RUN_ATTEMPT:'1'}
const plan={operation:'pg-stat-statements-capacity-stage/v1',work_issue:5609,source_pr:42,
 setting:'pg_stat_statements.max',desired:40000,restart_database:false,expected_effective:[5000,40000]}
function fixture(){return {mainSha:()=>env.GITHUB_SHA,getIssue:()=>({number:5609,state:'open'}),
 getPr:()=>({merged:true,merge_commit_sha:'b'.repeat(40),base:{ref:'main',repo:{full_name:'popcre/shared-db'}}})}}
const git=args=>args[0]==='rev-parse'&&args[1]==='HEAD'?env.GITHUB_SHA:args[0]==='merge-base'?'':'c'.repeat(40)
test('fixed profile qualifies only merged exact source and open owning issue',()=>{
 assert.equal(qualify(plan,env,fixture(),git).admitted,true)
 for(const changes of [{source_pr:null},{source_pr:0},{desired:50000},{restart_database:true},{work_issue:5610}])
  assert.throws(()=>qualify({...plan,...changes},env,fixture(),git))
 const closed=fixture();closed.getIssue=()=>({number:5609,state:'closed'});assert.throws(()=>qualify(plan,env,closed,git))
 const unmerged=fixture();unmerged.getPr=()=>({merged:false});assert.throws(()=>qualify(plan,env,unmerged,git))
})
test('stale main, source blob drift and run substitution fail before locks',()=>{
 const stale=fixture();stale.mainSha=()=>'d'.repeat(40);assert.throws(()=>qualify(plan,env,stale,git))
 assert.throws(()=>qualify(plan,env,fixture(),args=>args[0]==='rev-parse'&&args[1].startsWith('b'.repeat(40)+':')?'e'.repeat(40):git(args)))
 for(const changes of [{EXPECTED_HEAD:'b'.repeat(40)},{GITHUB_REF:'refs/heads/other'},
  {WORK_ISSUE:'5610'},{GITHUB_WORKFLOW_REF:'other'},{GITHUB_EVENT_NAME:'push'},{GITHUB_RUN_ID:'invalid'}])
  assert.throws(()=>qualify(plan,{...env,...changes},fixture(),git))
})
const now=Date.now()
const lease={kind:'preview-maintenance',holderId:'github-actions:100:1:pgss-stage:preview',headSha:env.GITHUB_SHA,
 githubRunId:'100',githubRunAttempt:1,generation:1,ownerSha:'f'.repeat(40),acquiredAt:new Date(now).toISOString()}
test('exact holder and generation fence refuses foreign expired or changed work',()=>{
 assert.equal(checkLease(lease,'preview',env,now).generation,1)
 for(const changes of [{holderId:'foreign'},{headSha:'c'.repeat(40)},{githubRunId:'101'},
  {githubRunAttempt:2},{generation:0},{ownerSha:'bad'},{kind:'production'},
  {acquiredAt:new Date(now-16*60*1000).toISOString()},{acquiredAt:new Date(now+2*60*1000).toISOString()}])
  assert.throws(()=>checkLease({...lease,...changes},'preview',env,now))
})
