import test from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync, chmodSync, symlinkSync } from 'node:fs'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { contractHash } from '../../agent-work-contract.mjs'
import { reviewStartedMarkerRef } from './constants.mjs'
import { reviewLeaseRefForAssignment } from './review-records.mjs'
import { qualifyCompletedUnrecordable, declaredDispositionOwner, readCompletedDescriptor, protectedDispositionBytes, completedUnrecordableRef, parseCompletedUnrecordable, readCompletedUnrecordable, assertReviewNotDisposed, commitCompletedDisposition, assertNoDisposedNegativeReuse } from './review-completed-unrecordable.mjs'
const owner='01a14247-5120-71f0-a78d-b9d477b46304',machine='fixture-host',reviewer='muse-spark-1.3-contributor'
const env={SHARED_DB_SESSION_ID:owner,CODEX_THREAD_ID:owner},dispatcher=`Codex coordinator chat ${owner} on ${machine}`
const hash=s=>createHash('sha256').update(s).digest('hex')
const H='a'.repeat(40),S='b'.repeat(40),A='c'.repeat(40),C='d'.repeat(40),M='e'.repeat(40)
const tuple={issue:4385,pr:4387,headSha:H,slot:1,sequence:6603,reviewer}
const write=(p,v)=>{mkdirSync(path.dirname(p),{recursive:true,mode:0o700});writeFileSync(p,typeof v==='string'?v:JSON.stringify(v),{mode:0o600})}
function fixture(t,{completionOverrides={},originalDispatcher=dispatcher}={}){
 const dir=mkdtempSync(path.join(tmpdir(),'completed-review-'));t.after(()=>rmSync(dir,{recursive:true,force:true}))
 const root=path.join(dir,'source');mkdirSync(root)
 const git=args=>execFileSync('git',['-C',root,...args],{encoding:'utf8',stdio:['ignore','pipe','pipe']})
 git(['init','-q']);git(['config','user.name','Fixture']);git(['config','user.email','fixture@example.invalid']);git(['remote','add','origin','https://github.com/popcre/shared-db.git'])
 const commit=(date)=>{git(['add','--all']);execFileSync('git',['-C',root,'commit','-qm','fixture'],{env:{...process.env,GIT_AUTHOR_DATE:date,GIT_COMMITTER_DATE:date},stdio:'pipe'});return git(['rev-parse','HEAD']).trim()}
 write(path.join(root,'.gitignore'),'.ai/\n');const base=commit('2026-10-15T01:00:00Z')
 const contract={schema_version:2,generation:1,evidence_parent:null,work_issue:4385,work_type:'repo-maintenance',route:'repo-maintenance',goal:'fixture repair',base_sha:base,dispatcher:originalDispatcher,worker:'Codex',branch:'codex/fixture',worktree:root,allowed_paths:['app.txt','.agent/work/4385/1/**'],file_writes:['app.txt','.agent/work/4385/1/**'],db_reads:[],db_writes:[],prohibited_actions:['no production'],required_checks:['node --test fixture.test.mjs'],assumptions:['fixture only'],stop_conditions:['stop on mismatch']}
 write(path.join(root,'app.txt'),'genuine fix\n');const impl=commit('2026-10-15T01:02:00Z')
 const report={schema_version:1,work_issue:4385,outcome:'ready-for-merge',pr:4387,migration_versions:[],contract_ref:'refs/db-contracts/4385/1',contract_sha256:contractHash(contract),head_sha:impl,files_changed:['app.txt'],db_reads:[],db_writes:[],checks:[{command:'node --test fixture.test.mjs',exit_code:0,evidence:'synthetic test'}],assumptions_resolved:[],stop_conditions_hit:[],...completionOverrides}
 write(path.join(root,'.agent/work/4385/1/contract.json'),contract);write(path.join(root,'.agent/work/4385/1/completion.json'),report);const head=commit('2026-10-15T01:03:00Z')
 const request={...tuple,headSha:head},sourceDigest='f'.repeat(64),packetDigest='1'.repeat(64)
 const receipt=path.join(root,'.ai/reviews/governed-source-11111111-1111-1111-1111-111111111111.json'),run='20261015T010500-123-456',packetDir=path.join(root,'.ai/reviews/packets/.ai-review-rlc-muse-fixture'),reportPath=path.join(root,`.ai/reviews/muse-final-check-${run}.md`)
 const body=`# muse final-check — ${run}\n| provider | \`muse\` |\n| repository | \`${root}\` |\n| runner | \`ai-review-engine\` (review-lifecycle-core/1) |\n| reviewed commit | \`${head}\` |\n| source digest | \`${sourceDigest}\` |\n| packet | \`${packetDigest}\` |\n| run | \`${run}\` |\n## Result\nSynthetic native fixture analysis confirms ${head} code scope.\n## Verdict\nAPPROVE\n`
 write(reportPath,body);write(path.join(packetDir,'.ai-review-packet'),`${root}\nfixture\nretained\n${packetDigest}\n`);write(path.join(packetDir,'identity.json'),{repository:root,head,base,source_digest:sourceDigest})
 const stateRoot=path.join(dir,'native-lifecycle'),key=hash('https://github.com/popcre/shared-db'),lifecycleFile=path.join(stateRoot,'runs',key,'muse','codex',`${run}.json`)
 const lifecycle={schema_version:1,status:'completed',provider:'muse',caller:'codex',implementer_engine:'codex',review_mode:'final-check',stale:false,failure_class:null,repository_root:root,normalized_upstream:'https://github.com/popcre/shared-db',repository_key:key,head,source_digest:sourceDigest,verdict:'APPROVE',packet_sha256:packetDigest,report_sha256:hash(body),started_at:'2026-10-15T01:05:00Z',finished_at:'2026-10-15T01:06:00Z',run_id:run,packet_dir:packetDir,report_path:reportPath}
 write(lifecycleFile,lifecycle)
 const descriptor=path.join(dir,'descriptor.json'),d={schema_version:1,contract_ref:'refs/db-contracts/4385/1',source_root:root,receipt_path:receipt,lifecycle_file:lifecycleFile};write(descriptor,d)
 const assignmentRef=`refs/db-review-assignments/4385-4387-${head}`,startRef=reviewStartedMarkerRef(request),leaseRef=reviewLeaseRefForAssignment(request,true),refs=new Map([[d.contract_ref,C],[assignmentRef,A],[startRef,S],[leaseRef,A]])
 const cursor=`db-coordination reviewer-cursor sequence=6603 reviewer=${reviewer} issue=4385 pr=4387 head=${head} slot=1`
 const commits=new Map([[C,{message:`db-agent-contract fixture\n\n${JSON.stringify(contract)}`,committedDate:'2026-10-15T01:01:00Z'}],[A,{message:cursor}],[S,{message:`db-coordination review-started issue=4385 pr=4387 head=${head} slot=1 sequence=6603 reviewer=${reviewer} at=2026-10-15T01:04:00Z session=- receipt-path=sha256:${hash(receipt)} source=sha256:${sourceDigest}`}]])
 let writes=0,reads=0
 const io={readRef:r=>{reads++;return refs.get(r)??null},getCommit:s=>{reads++;assert.ok(commits.has(s));return commits.get(s)},getPr:()=>({number:4387,state:'open',head:{sha:head,ref:'codex/fixture',repo:{full_name:'popcre/shared-db'}},base:{sha:base,ref:'main',repo:{full_name:'popcre/shared-db'}}}),readReviewRecords:rs=>new Map(rs.map(r=>[r,refs.has(r)?{sha:refs.get(r),commit:commits.get(refs.get(r))}:null])),makeOwnerCommit:message=>{writes++;commits.set(M,{message});return M},readReviewRefs:rs=>new Map(rs.map(r=>[r,refs.get(r)??null])),atomicReviewRefs:changes=>{writes++;for(const c of changes)assert.equal(refs.get(c.ref)??null,c.expected);for(const c of changes)c.sha?refs.set(c.ref,c.sha):refs.delete(c.ref)}}
 io.listRefs=prefix=>[...refs].filter(([r])=>r.startsWith(prefix)).map(([ref,sha])=>({ref,sha}))
 io.readPaidReviewStarts=()=>[{ref:startRef,sha:S,commit:commits.get(S)}]
 const deps={env:{...env,AI_REVIEW_LIFECYCLE_DIR:stateRoot},machine,packetRead:args=>{assert.ok(['verify-retained','resolve'].includes(args[0]));if(args[0]==='resolve')assert.deepEqual(args,['resolve',root,'--base',base,'--assert-head',head],'native packet resolve takes a positional repository');return args[0]==='resolve'?JSON.stringify({repository:root,head,source_digest:sourceDigest}):''}}
 return {root,dir,request,options:{...request,completedUnrecordableEvidenceFile:descriptor},descriptor,d,contract,lifecycle,lifecycleFile,reportPath,receipt,packetDir,sourceDigest,refs,commits,io,deps,leaseRef,startRef,assignmentRef,writes:()=>writes,reads:()=>reads,git}
}
test('strict original dispatcher identifies only the actual declared session and machine',()=>{
 for(const value of [dispatcher,dispatcher.replace('coordinator ','')])assert.deepEqual(declaredDispositionOwner(value,{env,machine}),{declared_owner:owner,machine,human_identity_authenticated:false})
 for(const d of [dispatcher+'\n',' '+dispatcher,dispatcher+' extra',dispatcher.replace('coordinator ','helper '),dispatcher.toUpperCase()])assert.throws(()=>declaredDispositionOwner(d,{env,machine}),/ownership-unproven/)
 for(const e of [{},{...env,SHARED_DB_SESSION_ID:owner+' '},{...env,CODEX_THREAD_ID:'another'}])assert.throws(()=>declaredDispositionOwner(dispatcher,{env:e,machine}),/ownership-unproven/)
 assert.throws(()=>declaredDispositionOwner(dispatcher,{env,machine:'other'}),/ownership-unproven/)
})
test('real Git native contract/completion plus native shaped evidence qualifies read-only',t=>{
 const f=fixture(t),p=qualifyCompletedUnrecordable(f.options,f.io,f.deps)
 assert.equal(p.record.observed_verdict,'APPROVE');assert.equal(p.record.authorizing,false);assert.equal(p.record.paid_attempt_consumed,true);assert.equal(f.writes(),0)
 assert.equal(p.record.bindings.length,4);assert.equal(JSON.stringify(p.record).includes(f.root),false)
})
for(const mutation of ['descriptorDuplicate','unknownField','receiptPresent','receiptLink','wrongOwner','wrongSource','latePublication','wrongStart','wrongVerdict','wrongReport','dirtySource','packetRefused','wrongPr','foreignLease','wrongLifecycleNamespace'])test(`qualified disposition refuses ${mutation} without mutation`,t=>{
 const f=fixture(t)
 if(mutation==='descriptorDuplicate')write(f.descriptor,readFileSync(f.descriptor,'utf8').replace('{','{"schema_version":1,'))
 if(mutation==='unknownField')write(f.descriptor,{...f.d,owner})
 if(mutation==='receiptPresent')write(f.receipt,'{}')
 if(mutation==='receiptLink')symlinkSync(f.reportPath,f.receipt)
 if(mutation==='wrongOwner')f.deps.env.SHARED_DB_SESSION_ID='other'
 if(mutation==='wrongSource')f.lifecycle.source_digest='0'.repeat(64)
 if(mutation==='latePublication')f.commits.get(C).committedDate='2026-10-15T01:05:00Z'
 if(mutation==='wrongStart')f.commits.get(S).message=f.commits.get(S).message.replace('sequence=6603','sequence=6604')
 if(mutation==='wrongVerdict')f.lifecycle.verdict='UNKNOWN'
 if(mutation==='wrongReport')write(f.reportPath,readFileSync(f.reportPath,'utf8')+'changed')
 if(mutation==='dirtySource')write(path.join(f.root,'app.txt'),'dirty')
 if(mutation==='packetRefused')f.deps.packetRead=()=>{throw Error('native packet refused')}
 if(mutation==='wrongPr')f.io.getPr=()=>({number:4387,state:'open',head:{sha:H}})
 if(mutation==='foreignLease')f.refs.set(f.leaseRef,H)
 if(mutation==='wrongLifecycleNamespace'){const other=path.join(f.dir,'forged.json');write(other,f.lifecycle);f.d.lifecycle_file=other;write(f.descriptor,f.d)}
 write(f.lifecycleFile,f.lifecycle)
 assert.throws(()=>qualifyCompletedUnrecordable(f.options,f.io,f.deps));assert.equal(f.writes(),0)
})
test('private input refuses public, linked, hardlinked and oversized descriptors',t=>{
 const f=fixture(t);chmodSync(f.descriptor,0o644);assert.throws(()=>readCompletedDescriptor(f.descriptor),/private/);chmodSync(f.descriptor,0o600)
 const link=path.join(f.dir,'link');symlinkSync(f.descriptor,link);assert.throws(()=>protectedDispositionBytes(link),/linked/)
 assert.throws(()=>protectedDispositionBytes(f.descriptor,1),/oversized/)
})
test('atomic disposition preserves assignment/start, deletes only exact own lease, remains spent and nonauthorizing',t=>{
 const f=fixture(t),p=qualifyCompletedUnrecordable(f.options,f.io,f.deps);f.refs.set('refs/mutex',H)
 const result=commitCompletedDisposition(p,H,f.io,'refs/mutex')
 assert.equal(result.authorizing,false);assert.equal(f.refs.get(f.assignmentRef),A);assert.equal(f.refs.get(f.startRef),S);assert.equal(f.refs.has(f.leaseRef),false)
 assert.throws(()=>assertReviewNotDisposed(f.request,f.io),/forbidden/)
 const again=qualifyCompletedUnrecordable(f.options,f.io,f.deps);assert.equal(again.prior.sha,M);assert.equal(commitCompletedDisposition(again,H,f.io,'refs/mutex').alreadyDisposed,true)
})
for(const changed of ['lease','mutex','record'])test(`atomic ${changed} race cannot release a foreign lease`,t=>{
 const f=fixture(t),p=qualifyCompletedUnrecordable(f.options,f.io,f.deps);f.refs.set('refs/mutex',H)
 const key=changed==='lease'?f.leaseRef:changed==='start'?f.startRef:changed==='mutex'?'refs/mutex':p.ref;f.refs.set(key,C)
 assert.throws(()=>commitCompletedDisposition(p,H,f.io,'refs/mutex'),/unproved/);assert.equal(f.refs.get(f.leaseRef),changed==='lease'?C:A)
})
test('atomic lost response reconciles once; sequential fallback is forbidden',t=>{
 const f=fixture(t),p=qualifyCompletedUnrecordable(f.options,f.io,f.deps);f.refs.set('refs/mutex',H)
 const atomic=f.io.atomicReviewRefs;let calls=0;f.io.atomicReviewRefs=c=>{calls++;atomic(c);throw Error('lost response')}
 assert.equal(commitCompletedDisposition(p,H,f.io,'refs/mutex').sha,M);assert.equal(calls,1)
 assert.throws(()=>commitCompletedDisposition(p,H,{...f.io,atomicReviewRefs:undefined},'refs/mutex'),/atomic ref support/)
})

test('completed nonapproval stays negative and is preserved, never labeled verdictless',t=>{
 const f=fixture(t);f.lifecycle.verdict='REJECT';const body=readFileSync(f.reportPath,'utf8').replace('## Verdict\nAPPROVE','## Verdict\nREJECT');write(f.reportPath,body);f.lifecycle.report_sha256=hash(body);write(f.lifecycleFile,f.lifecycle)
 const p=qualifyCompletedUnrecordable(f.options,f.io,f.deps);assert.equal(p.record.observed_verdict,'REJECT');assert.equal(p.record.paid_attempt_consumed,true);assert.equal(p.record.authorizing,false)
})
test('disposed tuple refuses a new lease occupant and mismatched existing proof',t=>{
 const f=fixture(t),p=qualifyCompletedUnrecordable(f.options,f.io,f.deps);f.refs.set('refs/mutex',H);commitCompletedDisposition(p,H,f.io,'refs/mutex')
 f.refs.set(f.leaseRef,C);assert.throws(()=>qualifyCompletedUnrecordable(f.options,f.io,f.deps),/new occupant/);assert.equal(f.refs.get(f.leaseRef),C)
 f.refs.delete(f.leaseRef);f.commits.get(M).message=f.commits.get(M).message.replace(p.record.proof_sha256,'0'.repeat(64));assert.throws(()=>qualifyCompletedUnrecordable(f.options,f.io,f.deps),/differs/)
})
for(const key of ['authorizing','paid_attempt_consumed','human_identity_authenticated','observed_verdict','bindings'])test(`durable disposition refuses malformed ${key}`,t=>{
 const f=fixture(t),p=qualifyCompletedUnrecordable(f.options,f.io,f.deps),r={...p.record,[key]:key==='observed_verdict'?'NONE':key==='bindings'?[]:!p.record[key]}
 assert.throws(()=>parseCompletedUnrecordable({message:`db-coordination completed-unrecordable\n${JSON.stringify(r)}`},f.request))
})

test('REAL native reader inventories dispositions in the same two remote reads and one immutable hydration',t=>{
 const f=fixture(t),tree=f.git(['rev-parse','HEAD^{tree}']).trim()
 const cursor=`db-coordination reviewer-cursor sequence=6603 reviewer=${reviewer} issue=4385 pr=4387 head=${f.request.headSha}`
 const actualAssignment=execFileSync('git',['-C',f.root,'commit-tree',tree,'-p',f.request.headSha],{input:cursor,encoding:'utf8'}).trim()
 f.git(['update-ref',f.assignmentRef,actualAssignment])
 const dispositionRef=completedUnrecordableRef(f.request),actualDisposition=execFileSync('git',['-C',f.root,'commit-tree',tree,'-p',f.request.headSha],{input:'synthetic non-authorizing record',encoding:'utf8'}).trim()
 f.git(['update-ref',dispositionRef,actualDisposition])
 const bare=path.join(f.dir,'remote.git');execFileSync('git',['clone','--mirror',f.root,bare],{stdio:'pipe'})

 const bin=path.join(f.dir,'bin'),calls=path.join(f.dir,'git-calls');mkdirSync(bin)
 const realGit=execFileSync('which',['git'],{encoding:'utf8'}).trim()
 write(path.join(bin,'git'),`#!/bin/sh\nprintf '%s\\n' "$*" >> "$FIXTURE_GIT_CALLS"\nif [ "$1" = ls-remote ] && [ "$2" = origin ]; then shift 2; exec '${realGit}' ls-remote "$FIXTURE_BARE_REMOTE" "$@"; fi\nexec '${realGit}' "$@"\n`);chmodSync(path.join(bin,'git'),0o700)
 const moduleUrl=new URL('../../manage-migration-author-lanes.mjs',import.meta.url).href
 const script=`import {githubIo,withReviewRequestBudget} from ${JSON.stringify(moduleUrl)};const r=withReviewRequestBudget(()=>githubIo.readReviewRecords([${JSON.stringify(f.assignmentRef)}],${JSON.stringify('refs/db-review-replacements/4385-4387-'+f.request.headSha)},null,${JSON.stringify(f.assignmentRef)}));console.log(JSON.stringify({matching:r.matching.map(x=>x.ref),dispositions:r.dispositionSnapshot.rows.map(x=>x.ref),hydrated:r.dispositionSnapshot.rows.every(x=>r.get(x.ref)?.sha===x.sha&&typeof r.get(x.ref)?.commit?.message==='string')}))`
 const run=()=>{write(calls,'');const output=execFileSync(process.execPath,['--input-type=module','-e',script],{cwd:f.root,encoding:'utf8',env:{...process.env,PATH:`${bin}:${process.env.PATH}`,FIXTURE_GIT_CALLS:calls,FIXTURE_BARE_REMOTE:bare,GIT_TERMINAL_PROMPT:'0'}});return {result:JSON.parse(output),calls:readFileSync(calls,'utf8').split('\n').filter(Boolean)}}
 const present=run();assert.deepEqual(present.result.dispositions,[dispositionRef]);assert.equal(present.result.hydrated,true);assert.deepEqual(present.result.matching,[f.assignmentRef])
 const remote=present.calls.filter(c=>c.startsWith('ls-remote origin '));assert.equal(remote.length,2);assert.ok(remote[0].includes('refs/db-review-dispositions/4385-4387-*'));assert.equal(present.calls.filter(c=>c==='cat-file --batch').length,1)
 execFileSync('git',['--git-dir',bare,'update-ref','-d',dispositionRef],{stdio:'pipe'})
 const absent=run();assert.equal(absent.result.dispositions.length,0);assert.equal(absent.calls.filter(c=>c.startsWith('ls-remote origin ')).length,2);assert.equal(absent.calls.filter(c=>c==='cat-file --batch').length,1)
})

import { disposeCompletedUnrecordableReview, runGitHubCommand, MUTEX_REF, releaseHeldMutexOnProcessExit } from '../../manage-migration-author-lanes.mjs'
function operationFixture(t,{replacement=false}={}){
 const f=replacement?replacementFixture(t):fixture(t),labels=[]
 const wire=(n,label)=>{for(let i=0;i<n;i++)runGitHubCommand(['api','synthetic-fixture'],{executor:()=>{labels.push(label);return '{}'}})}
 for(const name of ['getPr','getCommit','readRef','createRef']){
  const original=f.io[name]??((ref,sha)=>{if(f.refs.has(ref))return false;f.refs.set(ref,sha);return true})
  f.io[name]=(...args)=>{wire(1,name);return original(...args)}
 }
 f.io.getRateLimit=()=>{wire(2,'quota');return {remaining:5000,graphRemaining:5000,reset:0,graphReset:0}}
 let base=false
 f.io.makeOwnerCommit=message=>{wire(base?1:3,'commit');base=true;const sha=createHash('sha1').update(message).digest('hex');f.commits.set(sha,{message});return sha}
 f.io.atomicReviewMutexRelease=ownerSha=>f.io.atomicReviewRefs([{ref:MUTEX_REF,expected:ownerSha,sha:null}])
 const qualify=(options,io)=>qualifyCompletedUnrecordable(options,io,f.deps)
 return {...f,labels,qualify}
}
test('default dry-run performs only five bounded API reads, no commits/leases/provider writes',t=>{
 const f=operationFixture(t),before=[...f.refs]
 const result=disposeCompletedUnrecordableReview(f.options,f.io,{qualify:f.qualify})
 assert.equal(result.dryRun,true);assert.equal(result.authorizing,false);assert.deepEqual([...f.refs],before)
 assert.equal(f.labels.length,5);assert.equal(f.labels.includes('commit'),false)
})
test('applied isolated disposition uses15 API attempts within unchanged25 ceiling and releases its recoverable mutex',t=>{
 const f=operationFixture(t),result=disposeCompletedUnrecordableReview({...f.options,applyRecovery:true},f.io,{qualify:f.qualify})
 assert.equal(result.authorizing,false);assert.equal(result.paid_attempt_consumed,true)
 assert.equal(f.labels.length,15,JSON.stringify(f.labels));assert.equal(f.refs.has(MUTEX_REF),false)
 assert.equal(f.refs.get(f.assignmentRef),A);assert.equal(f.refs.get(f.startRef),S);assert.equal(f.refs.has(f.leaseRef),false)
 const lock=[...f.commits.values()].find(c=>c.message.startsWith('db-coordination reviewer-release-lock'))
 assert.ok(lock);assert.match(lock.message,/operation=completed-unrecordable/)
})
test('second mutex-held qualification detects source movement without disposition/lease writes',t=>{
 const f=operationFixture(t),before=[...f.refs],create=f.io.createRef
 f.io.createRef=(ref,sha)=>{const made=create(ref,sha);if(ref===MUTEX_REF&&made)write(path.join(f.root,'app.txt'),'racing source edit');return made}
 assert.throws(()=>disposeCompletedUnrecordableReview({...f.options,applyRecovery:true},f.io,{qualify:f.qualify}),/original physical source/)
 assert.deepEqual([...f.refs],before);assert.equal(f.refs.has(completedUnrecordableRef(f.request)),false)
})
test('native caller routing label remains supported without becoming chat ownership',t=>{
 const f=fixture(t),old=f.lifecycleFile,newFile=old.replace('/muse/codex/','/muse/zcode/')
 f.lifecycle.caller='zcode';write(newFile,f.lifecycle);f.d.lifecycle_file=newFile;write(f.descriptor,f.d)
 const p=qualifyCompletedUnrecordable(f.options,f.io,f.deps);assert.equal(p.record.declared_owner,owner);assert.equal(p.record.human_identity_authenticated,false)
})

test('an incomplete or changed batched disposition never becomes absence',t=>{
 const f=fixture(t),ref=completedUnrecordableRef(f.request)
 for(const record of [null,{sha:H},{sha:C}]){
  const io={...f.io,__completedDispositionSnapshot:()=>({rows:[{ref,sha:M}],records:new Map([[ref,record]])})}
  assert.throws(()=>readCompletedUnrecordable(f.request,io),/incomplete|changed/)
 }
 assert.throws(()=>readCompletedUnrecordable(f.request,{...f.io,readRef:()=>undefined}),/unreadable/)
})

for(const field of ['pr','work_issue'])test(`original completion cannot bind foreign ${field}`,t=>{
 const f=fixture(t,{completionOverrides:{[field]:9999}})
 assert.throws(()=>qualifyCompletedUnrecordable(f.options,f.io,f.deps),/completion lineage/)
})
for(const field of ['headRepo','baseRepo','branch','number'])test(`original source pair refuses ${field} mismatch`,t=>{
 const f=fixture(t),old=f.io.getPr
 f.io.getPr=()=>{const p=old();if(field==='headRepo')p.head.repo.full_name='foreign/shared-db';if(field==='baseRepo')p.base.repo.full_name='foreign/shared-db';if(field==='branch')p.head.ref='foreign/branch';if(field==='number')delete p.number;return p}
 assert.throws(()=>qualifyCompletedUnrecordable(f.options,f.io,f.deps),/original PR|contract\/source/)
})
for(const fault of ['later','malformed','invalid-time','duplicate','missing-original','unknown-provider','historical-muse-alias'])test(`native completion refuses ${fault} paid-start ambiguity`,t=>{
 const f=fixture(t),original={ref:f.startRef,sha:S,commit:f.commits.get(S)}
 const competitor={ref:f.startRef.replace('seq6603','seq6604'),sha:C,commit:{message:f.commits.get(S).message.replace('sequence=6603','sequence=6604').replace('01:04:00Z','01:05:30Z')}}
 if(fault==='malformed')competitor.commit.message='malformed competing immutable start'
 if(fault==='invalid-time')competitor.commit.message=competitor.commit.message.replace('2026-10-15T01:05:30Z','not-a-time')
 if(fault==='unknown-provider')competitor.commit.message=competitor.commit.message.replace(reviewer,'unknown-provider')
 if(fault==='historical-muse-alias')competitor.commit.message=competitor.commit.message.replace(reviewer,'muse-spark-1.2-contributor')
 f.io.readPaidReviewStarts=()=>fault==='duplicate'?[original,original]:fault==='missing-original'?[]:[original,competitor]
 assert.throws(()=>qualifyCompletedUnrecordable(f.options,f.io,f.deps),/paid.start|ambiguous|unknown provider/)
 assert.equal(f.writes(),0)
})
test('supported unrelated provider history is retained without creating false original-run ambiguity',t=>{
 const f=fixture(t),original={ref:f.startRef,sha:S,commit:f.commits.get(S)}
 const other={ref:f.startRef.replace('seq6603','seq6604'),sha:C,commit:{message:f.commits.get(S).message.replace('sequence=6603','sequence=6604').replace(reviewer,'glm-5.3').replace('01:04:00Z','01:05:30Z')}}
 f.io.readPaidReviewStarts=()=>[original,other]
 assert.equal(qualifyCompletedUnrecordable(f.options,f.io,f.deps).record.observed_verdict,'APPROVE')
})

import { assertOriginalGitContext } from './review-completed-unrecordable.mjs'
for(const key of ['GIT_DIR','GIT_WORK_TREE','GIT_INDEX_FILE','GIT_COMMON_DIR','GIT_CONFIG_PARAMETERS','GIT_CONFIG_COUNT','GIT_CONFIG_KEY_0','GIT_CONFIG_VALUE_0','GIT_GRAFT_FILE'])test(`injected ${key} refuses before source or repository access`,t=>{
 const f=fixture(t);let accessed=false
 f.deps.env[key]=key==='GIT_CONFIG_COUNT'?'1':'/unrelated/context'
 f.io.getPr=()=>{accessed=true;throw Error('must not read PR')};f.deps.git=()=>{accessed=true;throw Error('must not read source')}
 assert.throws(()=>qualifyCompletedUnrecordable(f.options,f.io,f.deps),/ambient Git context/);assert.equal(accessed,false)
})
test('real ambient GIT_DIR cannot redirect original physical source qualification',t=>{
 const f=fixture(t),other=path.join(f.dir,'other');mkdirSync(other);execFileSync('git',['init','-q',other]);const old=process.env.GIT_DIR;let accessed=false
 process.env.GIT_DIR=path.join(other,'.git')
 try{assert.throws(()=>qualifyCompletedUnrecordable(f.options,{...f.io,getPr:()=>{accessed=true;return f.io.getPr()}},f.deps),/ambient Git context/)}finally{if(old===undefined)delete process.env.GIT_DIR;else process.env.GIT_DIR=old}
 assert.equal(accessed,false);assert.equal(f.writes(),0)
})
test('actual Git top-level must match the original physical directory',t=>{
 const f=fixture(t);f.deps.git=()=>f.dir
 assert.throws(()=>qualifyCompletedUnrecordable(f.options,f.io,f.deps),/Git top-level/)
})
test('supported credential/SSH/proxy context is preserved and never blanket disabled',()=>{
 assert.doesNotThrow(()=>assertOriginalGitContext({GIT_SSH_COMMAND:'ssh -F private-supported-config',GIT_ASKPASS:'/supported/askpass',HTTPS_PROXY:'http://proxy.invalid',GIT_CONFIG_COUNT:'0'}))
})

// Exercise the actual native Git adapter against an owned bare remote. The two
// writers observe the same lease; no same-SHA/no-op ref is used as a CAS token.
for(const first of ['verdict','disposition'])test(`real bare Git ${first} wins exact lease once; losing publication cannot coexist`,t=>{
 const f=fixture(t),bare=path.join(f.dir,'atomic-remote.git')
 execFileSync('git',['clone','--bare',f.root,bare],{stdio:'pipe'})
 const run=(args)=>execFileSync('git',['--git-dir',bare,...args],{encoding:'utf8',stdio:['ignore','pipe','pipe']}).trim()
 const original=f.git(['rev-parse','HEAD']).trim(),lease='refs/db-review-active-v2/muse-spark-1.3-contributor/fixture',mutex='refs/db-coordination/reviewer-mutex',verdict='refs/db-review-verdicts/fixture',disposition='refs/db-review-dispositions/fixture'
 run(['update-ref',lease,original]);run(['update-ref',mutex,original])
 const entry=new URL('../../manage-migration-author-lanes.mjs',import.meta.url).href
 const push=changes=>execFileSync(process.execPath,['--input-type=module','-e',`import {githubIo} from ${JSON.stringify(entry)};githubIo.atomicReviewRefs(${JSON.stringify(changes)})`],{cwd:f.root,encoding:'utf8',stdio:'pipe'})
 f.git(['remote','set-url','origin',bare])
 const v=[{ref:verdict,expected:null,sha:original},{ref:lease,expected:original,sha:null}]
 const d=[{ref:disposition,expected:null,sha:original},{ref:lease,expected:original,sha:null},{ref:mutex,expected:original,sha:null}]
 push(first==='verdict'?v:d)
 assert.throws(()=>push(first==='verdict'?d:v))
 const exists=ref=>{try{return run(['rev-parse','--verify',ref])}catch{return null}}
 assert.equal(exists(first==='verdict'?verdict:disposition),original)
 assert.equal(exists(first==='verdict'?disposition:verdict),null)
 assert.equal(exists(lease),null)
 assert.equal(exists(mutex),first==='verdict'?original:null)
})
test('real bare Git changed mutex rejects whole disposition and preserves successor lock/lease',t=>{
 const f=fixture(t),bare=path.join(f.dir,'mutex-remote.git');execFileSync('git',['clone','--bare',f.root,bare],{stdio:'pipe'})
 const original=f.git(['rev-parse','HEAD']).trim(),tree=f.git(['rev-parse','HEAD^{tree}']).trim(),successor=f.git(['commit-tree',tree,'-m','synthetic successor']).trim()
 const git=args=>execFileSync('git',['--git-dir',bare,...args],{encoding:'utf8',stdio:['ignore','pipe','pipe']}).trim()
 git(['fetch','--no-tags',f.root,successor])
 const lease='refs/db-review-active-v2/muse-spark-1.3-contributor/fixture',mutex='refs/db-coordination/reviewer-mutex',disposition='refs/db-review-dispositions/fixture'
 git(['update-ref',lease,original]);git(['update-ref',mutex,successor]);f.git(['remote','set-url','origin',bare])
 const changes=[{ref:disposition,expected:null,sha:original},{ref:lease,expected:original,sha:null},{ref:mutex,expected:original,sha:null}]
 const entry=new URL('../../manage-migration-author-lanes.mjs',import.meta.url).href
 assert.throws(()=>execFileSync(process.execPath,['--input-type=module','-e',`import {githubIo} from ${JSON.stringify(entry)};githubIo.atomicReviewRefs(${JSON.stringify(changes)})`],{cwd:f.root,stdio:'pipe'}))
 assert.equal(git(['rev-parse',mutex]),successor);assert.equal(git(['rev-parse',lease]),original)
 assert.throws(()=>git(['rev-parse','--verify',disposition]))
})
for(const terminal of ['verdicts','verdict-replacements','failures','replacements'])test(`existing native ${terminal} refuses disposition before any write`,t=>{
 const f=fixture(t);f.refs.set(`refs/db-review-${terminal}/4385-4387-${f.request.headSha}`,C)
 assert.throws(()=>qualifyCompletedUnrecordable(f.options,f.io,f.deps),/existing native/);assert.equal(f.writes(),0)
})
test('missing or incomplete native terminal inventory fails closed',t=>{
 const f=fixture(t);assert.throws(()=>qualifyCompletedUnrecordable(f.options,{...f.io,listRefs:undefined},f.deps),/complete native/)
 assert.throws(()=>qualifyCompletedUnrecordable(f.options,{...f.io,listRefs:()=>null},f.deps),/incomplete/)
})
test('successful atomic disposition readback and cleanup preserve a newly acquired successor mutex',t=>{
 const f=operationFixture(t),atomic=f.io.atomicReviewRefs
 f.io.atomicReviewRefs=changes=>{atomic(changes);if(changes.some(c=>c.ref.startsWith('refs/db-review-dispositions/')))f.refs.set(MUTEX_REF,C)}
 const result=disposeCompletedUnrecordableReview({...f.options,applyRecovery:true},f.io,{qualify:f.qualify})
 assert.equal(result.mutex_released,true);assert.equal(f.refs.get(MUTEX_REF),C);assert.equal(f.refs.has(f.leaseRef),false)
 assert.equal(releaseHeldMutexOnProcessExit(),false,'successful operation cleared process-held mutex bookkeeping')
 const next=disposeCompletedUnrecordableReview(f.options,f.io,{qualify:f.qualify});assert.equal(next.alreadyDisposed,true);assert.equal(f.refs.get(MUTEX_REF),C)
})
test('real bare Git disposition accepts successor acquisition after atomic deletion before readback',t=>{
 const f=fixture(t),proof=qualifyCompletedUnrecordable(f.options,f.io,f.deps),bare=path.join(f.dir,'post-success-remote.git')
 execFileSync('git',['clone','--bare',f.root,bare],{stdio:'pipe'})
 const original=f.git(['rev-parse','HEAD']).trim(),tree=f.git(['rev-parse','HEAD^{tree}']).trim(),successor=f.git(['commit-tree',tree,'-m','synthetic successor']).trim()
 const git=args=>execFileSync('git',['--git-dir',bare,...args],{encoding:'utf8',stdio:['ignore','pipe','pipe']}).trim()
 git(['fetch','--no-tags',f.root,successor])
 const mutex='refs/db-coordination/reviewer-mutex';git(['update-ref',proof.leaseRef,original]);git(['update-ref',mutex,original]);f.git(['remote','set-url','origin',bare]);proof.leaseSha=original
 const entry=new URL('../../manage-migration-author-lanes.mjs',import.meta.url).href
 const io={makeOwnerCommit:message=>f.git(['commit-tree',tree,'-m',message]).trim(),atomicReviewRefs:changes=>{
  assert.equal(changes.length,3);assert.equal(changes.every(c=>c.sha!==c.expected),true)
  execFileSync(process.execPath,['--input-type=module','-e',`import {githubIo} from ${JSON.stringify(entry)};githubIo.atomicReviewRefs(${JSON.stringify(changes)})`],{cwd:f.root,stdio:'pipe'})
  git(['update-ref',mutex,successor])
 },readReviewRefs:refs=>new Map(refs.map(ref=>{try{return [ref,git(['rev-parse','--verify',ref])]}catch{return [ref,null]}}))}
 const result=commitCompletedDisposition(proof,original,io,mutex)
 assert.equal(result.mutex_released,true);assert.equal(git(['rev-parse',mutex]),successor)
 assert.equal(git(['rev-parse',proof.ref]),result.sha);assert.throws(()=>git(['rev-parse','--verify',proof.leaseRef]))
})
test('atomic disposition refuses missing or unreadable mutex readback',t=>{
 for(const missing of [undefined,'not-a-sha']){
  const f=fixture(t),proof=qualifyCompletedUnrecordable(f.options,f.io,f.deps);f.refs.set('refs/mutex',H)
  const read=f.io.readReviewRefs;f.io.readReviewRefs=refs=>{const rows=read(refs);missing===undefined?rows.delete('refs/mutex'):rows.set('refs/mutex',missing);return rows}
  assert.throws(()=>commitCompletedDisposition(proof,H,f.io,'refs/mutex'),/readback mismatch/)
 }
})
for(const kind of ['verdicts','verdict-replacements'])test(`archived native ${kind} still refuses missing-receipt disposition`,t=>{
 const f=fixture(t);f.refs.set(`refs/db-review-archived-verdicts/db-review-${kind}/4385-4387-${f.request.headSha}`,C)
 assert.throws(()=>qualifyCompletedUnrecordable(f.options,f.io,f.deps),/existing native/)
})
test('another slot native terminal state does not erase this independently held slot',t=>{
 const f=fixture(t);f.refs.set(`refs/db-review-verdicts/4385-4387-${f.request.headSha}-slot2`,C)
 assert.equal(qualifyCompletedUnrecordable(f.options,f.io,f.deps).record.slot,1)
})
test('malformed native terminal inventory cannot disappear as absence',t=>{
 const f=fixture(t);f.refs.set(`refs/db-review-failures/4385-4387-${f.request.headSha}-unknown`,C)
 assert.throws(()=>qualifyCompletedUnrecordable(f.options,f.io,f.deps),/identity malformed/)
})

// A genuine native-shaped initial GLM start/release and canonical Muse successor.
function replacementFixture(t,{originalDispatcher=dispatcher.replace('coordinator ','')}={}){
 const f=fixture(t,{originalDispatcher}),R='2'.repeat(40),F='3'.repeat(40),P='4'.repeat(40),sequence=6600
 const failureRef=`refs/db-review-failures/4385-4387-${f.request.headSha}-${sequence}`
 const replacementRef=`refs/db-review-replacements/4385-4387-${f.request.headSha}-${sequence}`
 const initialRequest={...f.request,sequence,reviewer:'glm-5.3'},initialStartRef=reviewStartedMarkerRef(initialRequest)
 f.commits.set(A,{message:`db-coordination reviewer-cursor sequence=${sequence} reviewer=glm-5.3 issue=4385 pr=4387 head=${f.request.headSha} slot=1`})
 f.commits.set(F,{message:`db-coordination reviewer-failure-release reviewer=glm-5.3 issue=4385 pr=4387 head=${f.request.headSha} failed-sequence=${sequence} code=wrapper_terminal_failure verdict=none artifact=none replacement=none`})
 f.commits.set(R,{message:`db-coordination reviewer-replacement sequence=6603 reviewer=${reviewer} issue=4385 pr=4387 head=${f.request.headSha} slot=1 failed-sequence=${sequence} prior-sequence=6602 failure-ref=${F}`})
 f.commits.set(P,{message:`db-coordination review-started issue=4385 pr=4387 head=${f.request.headSha} slot=1 sequence=${sequence} reviewer=glm-5.3 at=2026-10-15T01:03:30Z session=- receipt-path=sha256:${'2'.repeat(64)} source=sha256:${f.sourceDigest}`})
 f.refs.set(failureRef,F);f.refs.set(replacementRef,R);f.refs.set(initialStartRef,P);f.refs.set(f.leaseRef,R)
 f.io.readPaidReviewStarts=()=>[{ref:initialStartRef,sha:P,commit:f.commits.get(P)},{ref:f.startRef,sha:S,commit:f.commits.get(S)}]
 return {...f,R,F,P,failureRef,replacementRef,initialStartRef,initialRequest}
}
for(const originalDispatcher of [dispatcher,dispatcher.replace('coordinator ','')])test(`schema2 canonical replacement preserves exact original dispatcher: ${originalDispatcher.split(' chat')[0]}`,t=>{
 const f=replacementFixture(t,{originalDispatcher}),p=qualifyCompletedUnrecordable(f.options,f.io,f.deps)
 assert.equal(p.record.schema_version,2);assert.equal(p.record.declared_dispatcher,originalDispatcher);assert.equal(p.record.bindings.length,7)
 assert.deepEqual(p.record.bindings.map(b=>b.ref),[f.d.contract_ref,f.assignmentRef,f.initialStartRef,f.failureRef,f.replacementRef,f.startRef,f.leaseRef])
 assert.equal(p.record.bindings[6].sha,f.R);assert.equal(f.writes(),0)
 assert.deepEqual(parseCompletedUnrecordable({message:`db-coordination completed-unrecordable\n${JSON.stringify(p.record)}`},f.request),p.record)
})
test('ordinary original Codex dispatcher uses explicit schema2 with four ordered initial bindings',t=>{
 const originalDispatcher=dispatcher.replace('coordinator ',''),f=fixture(t,{originalDispatcher}),p=qualifyCompletedUnrecordable(f.options,f.io,f.deps)
 assert.equal(p.record.schema_version,2);assert.equal(p.record.declared_dispatcher,originalDispatcher);assert.equal(p.record.bindings.length,4)
 assert.equal(parseCompletedUnrecordable({message:`db-coordination completed-unrecordable\n${JSON.stringify(p.record)}`}).declared_dispatcher,originalDispatcher)
})
for(const mutation of ['releaseAbsent','replacementAbsent','startAbsent','wrongFailureSha','wrongInitialReviewer','wrongReleaseReviewer','wrongReleaseSequence','unsupportedCause','decisionPresent','badPriorSequence','wrongReplacementSequence','legacyAlias','multihop','changedInitialDigest'])test(`schema2 replacement refuses ${mutation} before writes`,t=>{
 const f=replacementFixture(t)
 if(mutation==='releaseAbsent')f.refs.delete(f.failureRef)
 if(mutation==='replacementAbsent')f.refs.delete(f.replacementRef)
 if(mutation==='startAbsent')f.refs.delete(f.initialStartRef)
 if(mutation==='wrongFailureSha')f.commits.get(f.R).message=f.commits.get(f.R).message.replace(f.F,C)
 if(mutation==='wrongInitialReviewer')f.commits.get(A).message=f.commits.get(A).message.replace('glm-5.3','step-5-preview')
 if(mutation==='wrongReleaseReviewer')f.commits.get(f.F).message=f.commits.get(f.F).message.replace('glm-5.3','step-5-preview')
 if(mutation==='wrongReleaseSequence')f.commits.get(f.F).message=f.commits.get(f.F).message.replace('failed-sequence=6600','failed-sequence=6599')
 if(mutation==='unsupportedCause')f.commits.get(f.F).message=f.commits.get(f.F).message.replace('wrapper_terminal_failure','reviewer_cannot_emit_governed_verdict')
 if(mutation==='decisionPresent')f.commits.get(f.F).message=f.commits.get(f.F).message.replace('verdict=none','verdict=APPROVE')
 if(mutation==='badPriorSequence')f.commits.get(f.R).message=f.commits.get(f.R).message.replace('prior-sequence=6602','prior-sequence=6603')
 if(mutation==='wrongReplacementSequence')f.commits.get(f.R).message=f.commits.get(f.R).message.replace('sequence=6603','sequence=6604')
 if(mutation==='legacyAlias'){f.refs.set(f.replacementRef.replace(/-6600$/,''),f.R);f.refs.delete(f.replacementRef)}
 if(mutation==='multihop')f.refs.set(f.replacementRef.replace(/-6600$/,'-6601'),f.R)
 if(mutation==='changedInitialDigest')f.commits.get(f.P).message=f.commits.get(f.P).message.replace(f.sourceDigest,'0'.repeat(64))
 assert.throws(()=>qualifyCompletedUnrecordable(f.options,f.io,f.deps));assert.equal(f.writes(),0)
})
for(const mutate of ['dispatcher','bindingOrder','bindingDuplicate','failureTuple','leaseSha','schemaDowngrade'])test(`schema2 durable record rejects ${mutate}`,t=>{
 const f=replacementFixture(t),p=qualifyCompletedUnrecordable(f.options,f.io,f.deps),r=structuredClone(p.record)
 if(mutate==='dispatcher')r.declared_dispatcher+='\n'
 if(mutate==='bindingOrder')[r.bindings[2],r.bindings[3]]=[r.bindings[3],r.bindings[2]]
 if(mutate==='bindingDuplicate')r.bindings[2]={...r.bindings[1]}
 if(mutate==='failureTuple')r.bindings[3].ref=r.bindings[3].ref.replace('4385-4387','4385-4388')
 if(mutate==='leaseSha')r.bindings[6].sha=A
 if(mutate==='schemaDowngrade')r.schema_version=1
 assert.throws(()=>parseCompletedUnrecordable({message:`db-coordination completed-unrecordable\n${JSON.stringify(r)}`}))
})
for(const provider of ['muse-spark-1.3-contributor','glm-5.3'])test(`schema2 refuses an extra ${provider} start even after original completion`,t=>{
 const f=replacementFixture(t),extra={...f.request,sequence:6604,reviewer:provider},extraRef=reviewStartedMarkerRef(extra),T='5'.repeat(40)
 f.commits.set(T,{message:`db-coordination review-started issue=4385 pr=4387 head=${f.request.headSha} slot=1 sequence=6604 reviewer=${provider} at=2026-10-15T01:07:00Z session=- receipt-path=sha256:${'3'.repeat(64)} source=sha256:${f.sourceDigest}`})
 const previous=f.io.readPaidReviewStarts;f.io.readPaidReviewStarts=()=>[...previous(),{ref:extraRef,sha:T,commit:f.commits.get(T)}]
 assert.throws(()=>qualifyCompletedUnrecordable(f.options,f.io,f.deps),/another same-slot/);assert.equal(f.writes(),0)
})
test('schema2 capacity fails closed before disposition when an earlier equivalent decision consumes the remaining round',t=>{
 const f=replacementFixture(t),T='5'.repeat(40),oldHead='6'.repeat(40),oldRef=reviewStartedMarkerRef({...f.request,headSha:oldHead,sequence:6599})
 f.commits.set(T,{message:`db-coordination review-started issue=4385 pr=4387 head=${oldHead} slot=1 sequence=6599 reviewer=${reviewer} at=2026-10-15T01:03:00Z session=- receipt-path=sha256:${'3'.repeat(64)} source=sha256:${f.sourceDigest}`})
 const previous=f.io.readPaidReviewStarts;f.io.readPaidReviewStarts=()=>[{ref:oldRef,sha:T,commit:f.commits.get(T)},...previous()]
 f.io.reviewContentComparison=(before,after)=>({before:f.sourceDigest,after:f.sourceDigest,budgetProof:{schema:1,before,after,protectedMain:f.request.headSha,kind:'unchanged'}})
 assert.throws(()=>qualifyCompletedUnrecordable(f.options,f.io,f.deps),/two paid attempts/);assert.equal(f.writes(),0)
})
for(const applyRecovery of [false,true])test(`schema2 native operation stays within unchanged25 request ceiling: apply=${applyRecovery}`,t=>{
 const f=operationFixture(t,{replacement:true}),before=new Map(f.refs)
 const result=disposeCompletedUnrecordableReview({...f.options,applyRecovery},f.io,{qualify:f.qualify})
 assert.equal(result.authorizing,false);assert.equal(result.paid_attempt_consumed,true);assert.ok(f.labels.length<=25,JSON.stringify(f.labels))
 for(const ref of [f.d.contract_ref,f.assignmentRef,f.initialStartRef,f.failureRef,f.replacementRef,f.startRef])assert.equal(f.refs.get(ref),before.get(ref))
 assert.equal(f.refs.has(f.leaseRef),!applyRecovery)
})
for(const changed of ['failure','replacement','initialStart'])test(`schema2 locked qualification refuses changed ${changed} evidence without disposition`,t=>{
 const f=operationFixture(t,{replacement:true}),create=f.io.createRef,target=changed==='failure'?f.failureRef:changed==='replacement'?f.replacementRef:f.initialStartRef
 f.io.createRef=(ref,sha)=>{const made=create(ref,sha);if(ref===MUTEX_REF&&made)f.refs.set(target,C);return made}
 assert.throws(()=>disposeCompletedUnrecordableReview({...f.options,applyRecovery:true},f.io,{qualify:f.qualify}));assert.equal(f.refs.get(f.leaseRef),f.R);assert.equal(f.refs.has(completedUnrecordableRef(f.request)),false)
})
test('schema2 consumed replacement stays idempotent and cannot be attributed to the other original spelling',t=>{
 const f=replacementFixture(t),p=qualifyCompletedUnrecordable(f.options,f.io,f.deps);f.refs.set('refs/mutex',H)
 commitCompletedDisposition(p,H,f.io,'refs/mutex');assert.ok(qualifyCompletedUnrecordable(f.options,f.io,f.deps).prior)
 const record=JSON.parse(f.commits.get(M).message.split('\n').slice(1).join('\n'));record.declared_dispatcher=dispatcher
 f.commits.get(M).message=`db-coordination completed-unrecordable\n${JSON.stringify(record)}`
 assert.throws(()=>qualifyCompletedUnrecordable(f.options,f.io,f.deps),/differs from the exact original proof/)
})

test('schema2 exact-start inventory preserves supported null tombstones without charging or admitting another paid start',t=>{
 const f=replacementFixture(t),T='5'.repeat(40),ref=reviewStartedMarkerRef({...f.request,sequence:6604})
 const message=`db-coordination reviewer-silence-release reviewer=${reviewer} issue=4385 pr=4387 head=${f.request.headSha} sequence=6604 code=silent_worker_observed probe=${C} observed-at=2026-10-15T01:06:00Z confirmed-at=2026-10-15T01:07:00Z verdict=none artifact=none replacement=none`
 const previous=f.io.readPaidReviewStarts;f.io.readPaidReviewStarts=()=>[...previous(),{ref,sha:T,commit:{message}}]
 assert.equal(qualifyCompletedUnrecordable(f.options,f.io,f.deps).record.bindings.length,7);assert.equal(f.writes(),0)
})

test('schema2 preserves native REJECT and blocks metadata-only laundering',t=>{
 const f=replacementFixture(t);f.lifecycle.verdict='REJECT'
 const body=readFileSync(f.reportPath,'utf8').replace('## Verdict\nAPPROVE','## Verdict\nREJECT');write(f.reportPath,body);f.lifecycle.report_sha256=hash(body);write(f.lifecycleFile,f.lifecycle)
 const p=qualifyCompletedUnrecordable(f.options,f.io,f.deps);f.refs.set('refs/mutex',H)
 const result=commitCompletedDisposition(p,H,f.io,'refs/mutex');assert.equal(result.observed_verdict,'REJECT');assert.equal(result.authorizing,false)
 const headSha='6'.repeat(40);f.io.reviewContentComparison=()=>({budgetProof:{kind:'unchanged',before:f.request.headSha,after:headSha}})
 assert.throws(()=>assertNoDisposedNegativeReuse({...f.request,headSha},f.io),/genuine code-correction/)
})
test('unsupported native REVISE lifecycle refuses before writes; durable REVISE reader stays negative',t=>{
 const f=replacementFixture(t),p=qualifyCompletedUnrecordable(f.options,f.io,f.deps)
 f.lifecycle.verdict='REVISE';const body=readFileSync(f.reportPath,'utf8').replace('## Verdict\nAPPROVE','## Verdict\nREVISE');write(f.reportPath,body);f.lifecycle.report_sha256=hash(body);write(f.lifecycleFile,f.lifecycle)
 assert.throws(()=>qualifyCompletedUnrecordable(f.options,f.io,f.deps),/lifecycle review/);assert.equal(f.writes(),0)
 // Reader compatibility is separate from qualification of a real native run.
 const record={...p.record,observed_verdict:'REVISE'};f.commits.set(M,{message:`db-coordination completed-unrecordable\n${JSON.stringify(record)}`});f.refs.set(p.ref,M)
 assert.equal(readCompletedUnrecordable(f.request,f.io).observed_verdict,'REVISE')
 assert.throws(()=>assertNoDisposedNegativeReuse({...f.request,headSha:'6'.repeat(40)},f.io),/genuine code-correction/)
})
