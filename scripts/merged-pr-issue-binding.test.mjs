import assert from 'node:assert/strict'
import test from 'node:test'
import { parseMergedPrIssueBinding, verifyMergedPrIssueBinding, withMergedPrIssueBinding, resolveAdmittedIssueForPr } from './manage-migration-author-lanes.mjs'

const HEAD='f'.repeat(40)
function fixture(overrides={}){
  const state={
    pr:{number:2726,merged_at:'2026-09-11T22:49:13Z',merge_commit_sha:'e'.repeat(40),head:{sha:HEAD,ref:'codex/issue-2506-production-performance-2714'},body:'Repairs #2506.\n\nWork issue #2506; active claim #2722; orchestrator #2714.'},
    completion:{work_issue:2506,pr:2726,migration_versions:['20260911213429']},
    files:[{filename:'.agent/completion.json',status:'added'},{filename:'supabase/migrations/20260911213429_popsg_search.sql',status:'added'}],
    linked:[],
    refs:new Set(['refs/db-claims/20260911213429']),
    ...overrides,
  }
  const io={
    getPr:()=>state.pr,
    getIssue:(n)=>({number:n,state:state.issueState??'open'}),
    getFileAt:(file,ref)=>{assert.equal(file,'.agent/completion.json');assert.equal(ref,HEAD);return typeof state.completion==='string'?state.completion:JSON.stringify(state.completion)},
    getPrFiles:()=>state.files,
    readRef:(ref)=>state.refs.has(ref)?'a'.repeat(40):null,
    closingIssuesForPr:(n)=>{state.closingCalls=(state.closingCalls??0)+1;return state.linked},
  }
  return {io,state}
}

test('binding parses only exact PR:ISSUE',()=>{
  assert.deepEqual(parseMergedPrIssueBinding('2726:2506'),{pr:2726,issue:2506})
  for(const bad of ['2506','2726:','x:1','0:1','2726:2506:1','2726, 2506'])assert.throws(()=>parseMergedPrIssueBinding(bad),/exactly PR:ISSUE/)
})

test('a merged PR with no closing link binds when every record agrees',()=>{
  const {io}=fixture(),lines=[]
  const bound=withMergedPrIssueBinding(io,'2726:2506',(line)=>lines.push(line))
  assert.deepEqual(bound.closingIssuesForPr(2726),[{number:2506,state:'open',bound:true}])
  assert.match(lines[0],/PR #2726 -> issue #2506/)
  assert.deepEqual(bound.closingIssuesForPr(9),[],'other PRs keep their real closing links')
  const lazy=fixture({pr:null}),other=withMergedPrIssueBinding(lazy.io,'2726:2506')
  assert.deepEqual(other.closingIssuesForPr(9),[],'an unrelated PR never triggers verification')
  assert.equal(bound.getPr().number,2726,'every other io method is inherited')
})

test('a real matching closing link wins and a disagreeing one refuses',()=>{
  assert.deepEqual(withMergedPrIssueBinding(fixture({linked:[{number:2506,state:'open'}]}).io,'2726:2506').closingIssuesForPr(2726),[{number:2506,state:'open'}])
  assert.throws(()=>withMergedPrIssueBinding(fixture({linked:[{number:77}]}).io,'2726:2506').closingIssuesForPr(2726),/already closes #77/)
})

test('every mismatch refuses the binding',()=>{
  const cases=[
    [{pr:{...fixture().state.pr,merged_at:null}},/not merged/],
    [{pr:{...fixture().state.pr,body:'no work line'}},/exactly one "Work issue #2506"; found none/],
    [{pr:{...fixture().state.pr,body:'Work issue #2506. Work issue #2507.'}},/found 2506,2507/],
    [{pr:{...fixture().state.pr,head:{sha:HEAD,ref:'codex/issue-2507-x'}}},/names issue #2507/],
    [{completion:'not json'},/completion.json .* unreadable/],
    [{completion:{work_issue:2507,pr:2726,migration_versions:['20260911213429']}},/completion record names issue #2507/],
    [{completion:{work_issue:2506,pr:2725,migration_versions:['20260911213429']}},/PR #2725/],
    [{completion:{work_issue:2506,pr:2726,migration_versions:['20260911213430']}},/do not equal completion record/],
    [{files:[{filename:'docs/x.md',status:'added'}],completion:{work_issue:2506,pr:2726,migration_versions:[]}},/PR migrations none/],
    [{refs:new Set()},/no permanent claim reservation/],
    [{pr:{...fixture().state.pr,head:{sha:HEAD,ref:'codex/ISSUE-2507-x'}}},/names issue #2507/],
    [{pr:{...fixture().state.pr,body:'Work issue #2506.\nWork issue #2506.'}},/found 2506,2506/],
    [{issueState:'closed'},/is not open/],
    [{files:[{filename:'supabase/migrations/20260911213429_popsg_search.sql',previous_filename:'supabase/migrations/20260911213428_old.sql',status:'renamed'}]},/is renamed/],
    [{files:[{filename:'supabase/migrations/20260911213429_popsg_search.sql',status:'removed'}]},/is removed/],
  ]
  for(const [override,pattern] of cases){
    const {io}=fixture(override)
    assert.throws(()=>verifyMergedPrIssueBinding({pr:2726,issue:2506},io),pattern)
    assert.throws(()=>withMergedPrIssueBinding(io,'2726:2506').closingIssuesForPr(2726),pattern)
  }
})

test('the resolver still refuses a merged PR with no link and no binding',()=>{
  assert.throws(()=>resolveAdmittedIssueForPr(2726,fixture().io),/must close exactly one structural work issue; found 0/)
})
