import assert from 'node:assert/strict'
import test from 'node:test'
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { claimBody, formatRetirementRecord, main, parseAuthorLease, rebindClaimWorktree, renewExpiredClaim, resetRetirementSnapshot, resumeAuthorLease, transferClaimAuthor, transferExpiredMergedClaimAuthor } from './manage-migration-author-lanes.mjs'

const NOW=new Date('2026-09-28T12:00:00Z')
const HEAD='a'.repeat(40),VERSION='20260923181754',RESERVATION='d'.repeat(40)
const QUOTE='I authorize the exact guarded operator adoption for the expired claim.'
const ARTIFACT='artifact:'+'f'.repeat(40)
const args={issue:2110,claim:3378,pr:3391,headSha:HEAD,oldOwner:'old-author',newOwner:'new-author',
  branch:'codex/2110-old',worktree:'C:/old-remote',targetWorktree:'/tmp/new-author',
  abandonmentIssue:900,worktreeState:'remote',authorizationChatId:'root',authorizationQuote:QUOTE,recoveryArtifact:ARTIFACT,leaseHours:12}

function fixture(overrides={}){
  resetRetirementSnapshot()
  const claim={number:3378,state:'open',title:'CLAIM: #2110 frozen schema',body:claimBody({
    version:VERSION,objects:['table plm.art_piece_attachment'],owner:args.oldOwner,branch:args.branch,
    worktree:args.worktree,expiresAt:new Date('2026-09-26T00:00:00Z'),
  })}
  const work={number:2110,state:'open',body:['```db-work-scope','status: ready','work_type: structural','route: shared-db-orchestrator','priority: 1','writes:','  - table plm.art_piece_attachment','```'].join('\n')}
  const audit={number:900,state:'open',body:['```db-work-scope','status: ready','work_type: repo-maintenance','route: repo-maintenance','priority: 1','objects:','```','','```abandonment-audit','claim: 3378','pr: 3391','head_sha: '+HEAD,'owner: old-author','```'].join('\n')}
  const issues=new Map([[3378,claim],[2110,work],[900,audit]]),refs=new Map([['refs/db-claims/'+VERSION,RESERVATION]]),commits=new Map([[RESERVATION,{message:'db-coordination permanent version reservation'}]])
  let serial=0
  const io={
    issues,refs,commits,
    getIssue:(n)=>structuredClone(issues.get(Number(n))),
    updateIssue:(n,{body})=>{issues.get(Number(n)).body=body},
    openClaims:()=>[structuredClone(issues.get(3378))],
    getPr:()=>({state:'open',head:{sha:HEAD,ref:args.branch}}),
    getPrFiles:()=>[{filename:'supabase/migrations/'+VERSION+'_retire.sql',status:'added'}],
    prSources:()=>[{label:'PR #3391',branch:args.branch,objects:['table plm.art_piece_attachment'],versions:[VERSION]}],
    branchPulls:()=>[{number:3391,head:{sha:HEAD}}],
    orchestratorFlowAdapter:()=>({resolveMarker:()=>({live:true,calling_task:'root',task:'root'})}),
    verifyArtifact:(reference)=>reference===ARTIFACT?{sha:'f'.repeat(40)}:null,
    readCommitMessage:(sha)=>commits.get(sha)?.message??null,
    localWorktreeState:()=>({state:'absent'}),
    localClean:()=>true,localHead:()=>HEAD,localBranch:()=>args.branch,
    makeOwnerCommit:(message)=>{const sha=String(++serial).padStart(40,'0');commits.set(sha,{message});return sha},
    getCommit:(sha)=>commits.get(sha),
    createRef:(ref,sha)=>{if(refs.has(ref))return false;refs.set(ref,sha);return true},
    readRef:(ref)=>refs.get(ref)??null,
    deleteRef:(ref)=>{refs.delete(ref)},
    listRefs:(prefix)=>[...refs].filter(([ref])=>ref.startsWith(prefix+'/')).map(([ref,sha])=>({ref,sha})),
    wait:()=>{},
  }
  return Object.assign(io,overrides)
}

test('guarded adoption retains claim, version, objects and PR, records operator provenance before mutation, and replays idempotently',()=>{
  const io=fixture(),before=parseAuthorLease(io.issues.get(3378).body,NOW)
  const result=transferClaimAuthor(args,NOW,io),after=parseAuthorLease(io.issues.get(3378).body,NOW)
  assert.equal(result.idempotent,false)
  assert.equal(after.owner,'new-author')
  assert.equal(after.worktree,args.targetWorktree)
  assert.equal(after.version,before.version)
  assert.deepEqual(after.objects,before.objects)
  assert.equal(io.refs.get('refs/db-claims/'+VERSION),RESERVATION)
  const record=JSON.parse(io.commits.get(result.sha).message.split('claim-author-operator-adoption ')[1])
  assert.equal(record.human_identity_authenticated,false)
  assert.equal(record.authorization_quote,QUOTE)
  assert.equal(record.reservation_sha,RESERVATION)
  assert.equal(transferClaimAuthor(args,NOW,io).idempotent,true)
})

function quarantine(io,overrides={}){
  io.issues.get(3378).body=claimBody({version:VERSION,objects:['table plm.art_piece_attachment'],owner:args.oldOwner,branch:args.branch,
    worktree:args.worktree,expiresAt:new Date('2026-09-26T00:00:00Z'),capacityState:'relinquished',blockedOn:'issue:#900',worktreeState:'remote',...overrides})
}

test('exact quarantined successor adoption restores active capacity and removes quarantine metadata',()=>{
  const io=fixture();quarantine(io,{recoveryArtifact:ARTIFACT})
  const result=transferClaimAuthor(args,NOW,io),after=parseAuthorLease(io.issues.get(3378).body,NOW)
  assert.equal(after.capacityState,'active');assert.equal(after.active,true);assert.equal(after.capacityActive,true)
  assert.equal(after.blockedOn,null);assert.equal(after.worktreeState,null);assert.equal(after.recoveryArtifact,null)
  assert.equal(after.owner,args.newOwner);assert.equal(after.worktree,args.targetWorktree)
  assert.equal(after.version,VERSION);assert.deepEqual(after.objects,['table plm.art_piece_attachment'])
  assert.equal(io.refs.get('refs/db-claims/'+VERSION),RESERVATION)
  assert.equal(transferClaimAuthor(args,NOW,io).sha,result.sha)
})

test('quarantined adoption refuses mismatched metadata and unexpired or legacy leases without changing the claim',()=>{
  for(const [overrides,pattern] of [
    [{blockedOn:'issue:#901'},/exact abandonment blocker/],
    [{worktreeState:'absent'},/exact abandonment blocker/],
    [{recoveryArtifact:'artifact:'+'e'.repeat(40)},/exact abandonment blocker/],
    [{expiresAt:new Date('2026-09-29T00:00:00Z')},/exact expired old-author lease/],
  ]){
    const io=fixture();quarantine(io,overrides);const before=io.issues.get(3378).body
    assert.throws(()=>transferClaimAuthor(args,NOW,io),pattern);assert.equal(io.issues.get(3378).body,before)
    assert.equal([...io.refs.keys()].some(ref=>ref.startsWith('refs/db-claim-author-transfers/')),false)
  }
  const io=fixture();quarantine(io);io.issues.get(3378).body=io.issues.get(3378).body.replace('worktree_state: remote\n','')
  const before=io.issues.get(3378).body
  assert.throws(()=>transferClaimAuthor(args,NOW,io),/exact expired old-author lease/);assert.equal(io.issues.get(3378).body,before)
})

test('quarantined adoption retains exact evidence and collision checks',()=>{
  for(const [change,pattern] of [
    [io=>{io.issues.get(900).body=io.issues.get(900).body.replace('head_sha: '+HEAD,'head_sha: '+'b'.repeat(40))},/names head/],
    [io=>{io.verifyArtifact=()=>null},/cannot be dereferenced/],
    [io=>{io.localClean=()=>false},/successor worktree/],
    [io=>{io.prSources=()=>[{label:'PR #3391',branch:args.branch,objects:['table other.x'],versions:[VERSION]}]},/outside the claim/],
  ]){
    const io=fixture();quarantine(io);change(io);const before=io.issues.get(3378).body
    assert.throws(()=>transferClaimAuthor(args,NOW,io),pattern);assert.equal(io.issues.get(3378).body,before)
  }
})

test('takeover refuses stale evidence, missing authorization, collisions, and unclean successor before changing claim',()=>{
  const cases=[
    [(io)=>{io.getPr=()=>({state:'open',head:{sha:'b'.repeat(40),ref:args.branch}})},/head or branch changed/],
    [(io)=>{io.prSources=()=>[{label:'PR #3391',branch:args.branch,objects:['table other.x'],versions:[VERSION]}]},/outside the claim/],
    [(io)=>{io.localClean=()=>false},/successor worktree/],
    [(io)=>{io.orchestratorFlowAdapter=()=>({resolveMarker:()=>({live:false})})},/acting on abandonment evidence: claim-first session authority is required/],
    [(io)=>{io.openClaims=()=>[io.getIssue(3378),{number:1,body:claimBody({version:'20260923181755',objects:['table plm.art_piece_attachment'],owner:'other',branch:'other',worktree:'/tmp/other',expiresAt:new Date('2026-09-30T00:00:00Z')})}]},/object collision/],
    [(io)=>{io.refs.delete('refs/db-claims/'+VERSION)},/permanent version reservation/],
    [(io)=>{io.refs.set('refs/db-claims/'+VERSION,'not-a-commit')},/permanent version reservation/],
    [(io)=>{io.refs.set('refs/db-coordination/merge','other')},/stage is held/],
    [(io)=>{io.issues.get(900).body=io.issues.get(900).body.replace('head_sha: '+HEAD,'head_sha: '+'b'.repeat(40))},/names head/],
    [(io)=>{io.verifyArtifact=()=>null},/cannot be dereferenced/],
    [(io)=>{io.openClaims=()=>[io.getIssue(3378),{number:2,body:claimBody({version:'20260923181755',objects:['table other.x'],owner:'other',branch:'other',worktree:args.targetWorktree,expiresAt:new Date('2026-09-30T00:00:00Z')})}]},/successor worktree belongs/],
  ]
  for(const [change,pattern] of cases){
    const io=fixture();change(io);const before=io.issues.get(3378).body
    assert.throws(()=>transferClaimAuthor(args,NOW,io),pattern)
    assert.equal(io.issues.get(3378).body,before)
  }
})

test('takeover refuses a wrong declared old-worktree state and an altered decision tuple',()=>{
  const io=fixture(),before=io.issues.get(3378).body
  assert.throws(()=>transferClaimAuthor({...args,worktreeState:'clean'},NOW,io),/worktree state differs/)
  assert.throws(()=>transferClaimAuthor({...args,authorizationChatId:'wrong'},NOW,io),/chat ID does not match/)
  assert.throws(()=>transferClaimAuthor({...args,authorizationQuote:''},NOW,io),/verbatim user authorization/)
  assert.throws(()=>transferClaimAuthor({...args,recoveryArtifact:''},NOW,io),/recovery-artifact/)
  assert.equal(io.issues.get(3378).body,before)
})

test('takeover never changes claim when evidence-ref creation fails',()=>{
  const io=fixture(),before=io.issues.get(3378).body,create=io.createRef
  io.createRef=(ref,sha)=>ref.startsWith('refs/db-claim-author-transfers/')?false:create(ref,sha)
  assert.throws(()=>transferClaimAuthor(args,NOW,io),/could not be created/)
  assert.equal(io.issues.get(3378).body,before)
  assert.equal(io.refs.get('refs/db-claims/'+VERSION),RESERVATION)
})

test('an evidence record that cannot be read back is deleted and leaves no claim change',()=>{
  const io=fixture(),before=io.issues.get(3378).body,read=io.readRef
  let reads=0
  io.readRef=(ref)=>{
    if(ref.startsWith('refs/db-claim-author-transfers/')&&++reads<=13)return null
    return read(ref)
  }
  assert.throws(()=>transferClaimAuthor(args,NOW,io),/could not be read back/)
  assert.equal(io.issues.get(3378).body,before)
  assert.equal([...io.refs.keys()].some((key)=>key.startsWith('refs/db-claim-author-transfers/')),false)
})

test('branch injection characters are refused before any claim change',()=>{
  for(const branch of ['codex/2110 old','codex/2110`old','codex/2110\nold']){
    const io=fixture(),before=io.issues.get(3378).body
    assert.throws(()=>transferClaimAuthor({...args,branch},NOW,io),/forbidden character/)
    assert.equal(io.issues.get(3378).body,before)
  }
})

test('created evidence can finish an interrupted claim write without a second record',()=>{
  const io=fixture(),original=io.updateIssue
  io.updateIssue=()=>{throw new Error('interrupted')}
  assert.throws(()=>transferClaimAuthor(args,NOW,io),/interrupted/)
  const ref=[...io.refs.keys()].find((key)=>key.startsWith('refs/db-claim-author-transfers/'))
  assert.ok(ref)
  assert.equal(parseAuthorLease(io.issues.get(3378).body,NOW).owner,args.oldOwner)
  io.updateIssue=original
  const result=transferClaimAuthor(args,NOW,io)
  assert.equal(result.ref,ref)
  assert.equal(parseAuthorLease(io.issues.get(3378).body,NOW).owner,args.newOwner)
})

test('a failed post-write readback rolls the claim back and retries with the same record',()=>{
  const io=fixture(),original=io.getIssue
  let wrote=false
  const update=io.updateIssue
  io.updateIssue=(number,change)=>{update(number,change);wrote=true}
  io.getIssue=(number)=>{if(wrote){wrote=false;throw new Error('readback interrupted')}return original(number)}
  assert.throws(()=>transferClaimAuthor(args,NOW,io),/readback interrupted/)
  assert.equal(parseAuthorLease(io.issues.get(3378).body,NOW).owner,args.oldOwner)
  io.getIssue=original
  const ref=[...io.refs.keys()].find((key)=>key.startsWith('refs/db-claim-author-transfers/'))
  const result=transferClaimAuthor(args,NOW,io)
  assert.equal(result.idempotent,false)
  assert.equal(result.ref,ref)
  assert.equal(parseAuthorLease(io.issues.get(3378).body,NOW).owner,args.newOwner)
})

test('malformed adoption records cannot authorize a partial retry',()=>{
  for(const mutate of [
    (record)=>{record.human_identity_authenticated=true},
    (record)=>{delete record.authorization_quote},
    (record)=>{record.reservation_sha='not-a-commit'},
    (record)=>{record.old_owner=record.new_owner},
    (record)=>{record.branch=''},
    (record)=>{record.abandonment_issue=0},
    (record)=>{record.authorization_quote=' padded quote that is long enough '},
    (record)=>{record.old_worktree_state='not-a-state'},
    (record)=>{record.recovery_artifact=null},
  ]){
    const io=fixture();io.updateIssue=()=>{throw new Error('interrupted')}
    assert.throws(()=>transferClaimAuthor(args,NOW,io),/interrupted/)
    const ref=[...io.refs.keys()].find((key)=>key.startsWith('refs/db-claim-author-transfers/'))
    const sha=io.refs.get(ref),prefix='db-coordination claim-author-operator-adoption '
    const record=JSON.parse(io.commits.get(sha).message.slice(prefix.length));mutate(record)
    io.commits.get(sha).message=prefix+JSON.stringify(record)
    assert.throws(()=>transferClaimAuthor(args,NOW,io),/invalid exact fields/)
    assert.equal(parseAuthorLease(io.issues.get(3378).body,NOW).owner,args.oldOwner)
  }
})

test('an old author cannot resume, renew, or rebind after adoption',()=>{
  const io=fixture();transferClaimAuthor(args,NOW,io)
  const body=io.issues.get(3378).body
  assert.throws(()=>resumeAuthorLease({claim:3378,owner:args.oldOwner,leaseHours:12},NOW,io),/different owner/)
  assert.throws(()=>renewExpiredClaim({claim:3378,issue:2110,owner:args.oldOwner,branch:args.branch,worktree:args.worktree,pr:3391,headSha:HEAD,leaseHours:12},NOW,io),/owner, branch, or worktree mismatch/)
  assert.throws(()=>rebindClaimWorktree({claim:3378,issue:2110,owner:args.oldOwner,branch:args.branch,worktree:args.worktree,targetWorktree:'/tmp/another',pr:3391,headSha:HEAD},NOW,io),/claim owner changed/)
  assert.equal(io.issues.get(3378).body,body)
})

test('a changed permanent reservation after claim mutation rolls the claim back',()=>{
  const io=fixture(),original=io.updateIssue
  io.updateIssue=(number,change)=>{original(number,change);io.refs.set('refs/db-claims/'+VERSION,'e'.repeat(40))}
  assert.throws(()=>transferClaimAuthor(args,NOW,io),/reservation changed after adoption/)
  assert.equal(parseAuthorLease(io.issues.get(3378).body,NOW).owner,args.oldOwner)
})

test('retired successor worktree identity is refused',()=>{
  const io=fixture(),retiredVersion='20260901000000',retiredSha='e'.repeat(40)
  io.refs.set('refs/db-claims-retired/'+retiredVersion,retiredSha)
  io.commits.set(retiredSha,{message:formatRetirementRecord({schema_version:2,claim:12,pr:13,head_sha:'b'.repeat(40),branch:'old-branch',version:retiredVersion,worktree:'/TMP/NEW-AUTHOR/',worktree_state:'clean',decision:'owner-terminated',evidence:'artifact:'+'f'.repeat(40),successor_issue:null,created_at:'2026-09-20T00:00:00Z'})})
  assert.throws(()=>transferClaimAuthor(args,NOW,io),/terminally retired claim/)
})

test('a later expired successor can be adopted through a distinct immutable record',()=>{
  const io=fixture(),first=transferClaimAuthor(args,NOW,io)
  const later=new Date(NOW.valueOf()+13*3600000)
  io.issues.get(900).body=io.issues.get(900).body.replace('owner: old-author','owner: new-author')
  const secondArgs={...args,oldOwner:'new-author',newOwner:'third-author',worktree:args.targetWorktree,
    targetWorktree:'/tmp/third-author',authorizationQuote:'I authorize the third author to adopt the exact expired claim.'}
  const second=transferClaimAuthor(secondArgs,later,io)
  assert.notEqual(second.ref,first.ref)
  assert.equal(io.refs.get(first.ref),first.sha)
  assert.equal(io.refs.get(second.ref),second.sha)
  assert.equal(parseAuthorLease(io.issues.get(3378).body,later).owner,'third-author')
})

test('CLI transfer route parses the exact guarded inputs',()=>{
  const io=fixture(),log=console.log,dir=mkdtempSync(join(tmpdir(),'transfer-quote-'))
  const quoteFile=join(dir,'quote.txt');writeFileSync(quoteFile,QUOTE+'\r\n')
  console.log=()=>{}
  try{
    const argv=['--transfer-claim-author','--issue','2110','--claim-number','3378','--pr','3391',
      '--head-sha',HEAD,'--old-owner',args.oldOwner,'--new-owner',args.newOwner,'--branch',args.branch,
      '--worktree',args.worktree,'--target-worktree',args.targetWorktree,'--abandonment-issue','900',
      '--worktree-state','remote','--authorization-chat-id','root','--authorization-quote-file',quoteFile,'--recovery-artifact',ARTIFACT,'--lease-hours','12']
    assert.equal(main(argv,NOW,io),0)
    assert.equal(parseAuthorLease(io.issues.get(3378).body,NOW).owner,args.newOwner)
  }finally{console.log=log;rmSync(dir,{recursive:true,force:true})}
})

const MERGE='b'.repeat(40),MAIN='c'.repeat(40)
function mergedFixture(overrides={}){
  return fixture({getPr:()=>({state:'closed',merged:true,merge_commit_sha:MERGE,head:{sha:HEAD,ref:args.branch}}),
    mainSha:()=>MAIN,compareCommits:()=>({status:'ahead',behind_by:0}),
    prStructuralObjects:(pr,head)=>{assert.equal(pr,3391);assert.equal(head,HEAD);return ['table plm.art_piece_attachment']},
    prSources:()=>[],...overrides})
}
test('expired merged adoption preserves exact source and immutable record and replays',()=>{
  const io=mergedFixture(),before=parseAuthorLease(io.issues.get(3378).body,NOW)
  assert.throws(()=>transferClaimAuthor(args,NOW,io),/open PR/)
  const result=transferExpiredMergedClaimAuthor(args,NOW,io),after=parseAuthorLease(io.issues.get(3378).body,NOW)
  assert.equal(after.owner,args.newOwner);assert.equal(after.version,before.version);assert.deepEqual(after.objects,before.objects)
  const record=JSON.parse(io.commits.get(result.sha).message.split('claim-author-operator-adoption ')[1])
  assert.equal(record.kind,'merged-operator-adoption');assert.equal(record.source_merge_sha,MERGE);assert.equal(record.head_sha,HEAD)
  assert.equal(transferExpiredMergedClaimAuthor(args,NOW,io).idempotent,true)
})
test('merged adoption refuses active and relinquished leases even with exact source',()=>{
  for(const mutate of [body=>body.replace('2026-09-26T00:00:00.000Z','2026-09-29T00:00:00.000Z'),
    body=>claimBody({version:VERSION,objects:['table plm.art_piece_attachment'],owner:args.oldOwner,branch:args.branch,worktree:args.worktree,expiresAt:new Date('2026-09-26T00:00:00Z'),capacityState:'relinquished',blockedOn:'issue:#900',worktreeState:'remote',recoveryArtifact:ARTIFACT})]){
    const io=mergedFixture();io.issues.get(3378).body=mutate(io.issues.get(3378).body);const before=io.issues.get(3378).body
    assert.throws(()=>transferExpiredMergedClaimAuthor(args,NOW,io),/expired/);assert.equal(io.issues.get(3378).body,before)
  }
})
test('merged adoption refuses wrong source, missing ancestry, uncovered objects, stages and stale audit',()=>{
  for(const [override,pattern] of [
    [{getPr:()=>({state:'open',head:{sha:HEAD,ref:args.branch}})},/exact merged/],
    [{getPr:()=>({state:'closed',merged:true,merge_commit_sha:MERGE,head:{sha:'e'.repeat(40),ref:args.branch}})},/head or branch/],
    [{compareCommits:()=>({status:'diverged',behind_by:1})},/not contained/],
    [{mainSha:()=>null},/current main/],
    [{prStructuralObjects:()=>['table plm.unclaimed']},/outside the claim/],
    [{prStructuralObjects:()=>[]},/missing or ambiguous/],
  ]){const io=mergedFixture(override),before=io.issues.get(3378).body;assert.throws(()=>transferExpiredMergedClaimAuthor(args,NOW,io),pattern);assert.equal(io.issues.get(3378).body,before)}
  const io=mergedFixture();io.issues.get(900).body=io.issues.get(900).body.replace(HEAD,'e'.repeat(40));assert.throws(()=>transferExpiredMergedClaimAuthor(args,NOW,io),/now at/)
})
test('merged adoption readback failure rolls claim back and retries immutable record',()=>{
  const io=mergedFixture(),before=io.issues.get(3378).body,update=io.updateIssue;let writes=0
  io.updateIssue=(n,change)=>{update(n,change);if(++writes===1)throw new Error('interrupted merged write')}
  assert.throws(()=>transferExpiredMergedClaimAuthor(args,NOW,io),/interrupted merged write/);assert.equal(io.issues.get(3378).body,before)
  const ref=[...io.refs.keys()].find(k=>k.includes('db-claim-author-transfers/')),sha=io.refs.get(ref)
  io.updateIssue=update;assert.equal(transferExpiredMergedClaimAuthor(args,NOW,io).sha,sha)
})

test('merged adoption keeps reservations, rescue, collisions and every stage guarded',()=>{
  const cases=[
    [io=>io.refs.delete('refs/db-claims/'+VERSION),/permanent version reservation/],
    [io=>{io.verifyArtifact=()=>null},/cannot be dereferenced/],
    [io=>{io.localClean=()=>false},/successor worktree/],
    [io=>{io.orchestratorFlowAdapter=()=>({resolveMarker:()=>({live:false})})},/session authority/],
    [io=>{io.openClaims=()=>[io.getIssue(3378),{number:9,body:claimBody({version:'20260923181755',objects:['table plm.art_piece_attachment'],owner:'other',branch:'other',worktree:'/tmp/other',expiresAt:new Date('2026-09-30T00:00:00Z')})}]},/object collision/],
    ...['preview','merge','production'].map(stage=>[io=>io.refs.set('refs/db-coordination/'+stage,'other'),/stage is held/]),
  ]
  for(const [change,pattern]of cases){const io=mergedFixture();change(io);const before=io.issues.get(3378).body;assert.throws(()=>transferExpiredMergedClaimAuthor(args,NOW,io),pattern);assert.equal(io.issues.get(3378).body,before)}
})
test('merged adoption never accepts a rewritten merge identity on an immutable retry',()=>{
  const io=mergedFixture();const result=transferExpiredMergedClaimAuthor(args,NOW,io)
  const commit=io.commits.get(result.sha),prefix='db-coordination claim-author-operator-adoption ',record=JSON.parse(commit.message.slice(prefix.length));record.source_merge_sha='e'.repeat(40);commit.message=prefix+JSON.stringify(record)
  assert.throws(()=>transferExpiredMergedClaimAuthor(args,NOW,io),/differs from exact request/)
})

test('merged CLI operation is explicit and keeps ordinary transfer separate',()=>{
  const dir=mkdtempSync(join(tmpdir(),'merged-author-cli-')),quoteFile=join(dir,'quote.txt');writeFileSync(quoteFile,QUOTE)
  const io=mergedFixture(),log=console.log;console.log=()=>{}
  try{
    const argv=['--transfer-expired-merged-claim-author','--issue','2110','--claim-number','3378','--pr','3391','--head-sha',HEAD,'--old-owner',args.oldOwner,'--new-owner',args.newOwner,'--branch',args.branch,'--worktree',args.worktree,'--target-worktree',args.targetWorktree,'--abandonment-issue','900','--worktree-state','remote','--authorization-chat-id','root','--authorization-quote-file',quoteFile,'--recovery-artifact',ARTIFACT,'--lease-hours','12']
    assert.equal(main(argv,NOW,io),0);assert.equal(parseAuthorLease(io.issues.get(3378).body,NOW).owner,args.newOwner)
  }finally{console.log=log;rmSync(dir,{recursive:true,force:true})}
})
