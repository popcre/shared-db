import test from 'node:test'
import assert from 'node:assert/strict'
import { paidStart, assertPaidReviewCapacity, pauseActualReviewFailure, derivePaidContentProof } from './review-circuit-breaker.mjs'
const head='a'.repeat(40), next='b'.repeat(40), digest='c'.repeat(64)
const request={issue:3536,pr:4000,headSha:head,slot:1}
function row(seq=1,h=head,slot=1){return{ref:`refs/db-review-started/3536-4000-${h}-slot${slot}-seq${seq}`,sha:String(seq).padStart(40,'0')}}
function message(seq=1,h=head,slot=1){return`db-coordination review-started issue=3536 pr=4000 head=${h} slot=${slot} sequence=${seq} reviewer=glm-5.3 at=2026-10-06T18:00:00.000Z`}
function io(rows){return{listRefs:()=>rows,getCommit:sha=>({message:message(Number(sha))}),reviewContentComparison:()=>({before:digest,after:digest,budgetProof:{schema:1,before:head,after:next,protectedMain:head,kind:'unchanged'}})}}
test('zero and one paid attempts retain capacity',()=>{assert.equal(assertPaidReviewCapacity(request,io([])).remaining,2);assert.equal(assertPaidReviewCapacity(request,io([row()])).remaining,1)})
test('third paid draw refuses unchanged exact head',()=>assert.throws(()=>assertPaidReviewCapacity(request,io([row(),row(2)])),/third draw refused/))
test('evidence-only or empty-head refresh cannot reset cap',()=>assert.throws(()=>assertPaidReviewCapacity({...request,headSha:next},io([row(),row(2)])),/third draw refused/))
test('substantive byte change starts another round',()=>{const x=io([row(),row(2)]);x.reviewContentComparison=()=>({before:digest,after:'d'.repeat(64),budgetProof:{schema:1,before:head,after:next,protectedMain:head,kind:'substantive',historyCount:1}});assert.equal(assertPaidReviewCapacity({...request,headSha:next},x).remaining,2)})
test('unknown, malformed and failed comparison cannot reset',()=>{for(const proof of [null,{before:'unknown',after:digest}]){const x=io([row(),row(2)]);x.reviewContentComparison=()=>proof;assert.throws(()=>assertPaidReviewCapacity({...request,headSha:next},x),/proof unreadable/)}const x=io([row()]);x.reviewContentComparison=()=>{throw Error('fetch failed')};assert.throws(()=>assertPaidReviewCapacity({...request,headSha:next},x),/fetch failed/)})
test('independent slots have separate paid caps',()=>{const x=io([row(1,head,2),row(2,head,2)]);x.getCommit=sha=>({message:message(Number(sha),head,2)});assert.equal(assertPaidReviewCapacity(request,x).remaining,2)})
test('tampered scope, time or record refuses',()=>{for(const text of [message().replace('pr=4000','pr=4001'),message().replace('2026-10-06T18:00:00.000Z','unknown'),'PASS doctor repaired'])assert.throws(()=>paidStart(row(),{message:text}),/binding mismatch|unrecognized/)})
test('unstarted atomic reclaim is not a paid attempt',()=>{const text=`db-coordination reviewer-silence-release reviewer=glm-5.3 issue=3536 pr=4000 head=${head} sequence=1 code=silent_worker_observed probe=${'e'.repeat(40)} observed-at=2026-10-06T17:00:00Z confirmed-at=2026-10-06T18:00:00Z verdict=none artifact=none replacement=none`;assert.equal(paidStart(row(),{message:text}),null);assert.throws(()=>paidStart(row(),{message:text.replace('sequence=1','sequence=2')}),/unrecognized/)})
test('quoted or repeated doctor PASS never provides a reset',()=>{const x=io([row(),row(2)]);x.reinstatement=()=>({output:'PASS',fresh:true});assert.throws(()=>assertPaidReviewCapacity(request,x),/third draw refused/)})

test('pre-start independent-slot conflict is skipped only with exact scope',()=>{
 const text=`db-coordination reviewer-failure-replacement sequence=3 reviewer=stepfun-step-5-preview issue=3536 pr=4000 head=${head} slot=1 failed-sequence=1 prior-sequence=2 failure-ref=self failed-reviewer=glm-5.3 code=slot_independence_conflict verdict=none artifact=none`
 assert.equal(paidStart(row(),{message:text}),null)
 assert.throws(()=>paidStart(row(),{message:text.replace('slot=1','slot=2')}),/unrecognized/)
 assert.throws(()=>paidStart(row(),{message:text.replace('slot_independence_conflict','provider_unavailable')}),/unrecognized/)
})

test('changing work issue cannot reset the same PR paid cap',()=>{
 const x=io([row(),row(2)])
 assert.throws(()=>assertPaidReviewCapacity({...request,issue:3537},x),/third draw refused/)
})

test('actual quota/outage release pauses only exact paid provider failure',()=>{
 const record={...request,failedSequence:1,reviewer:'glm-5.3',failureCode:'insufficient_quota',failureSha:'f'.repeat(40)}
 const release=`db-coordination reviewer-failure-release reviewer=glm-5.3 issue=3536 pr=4000 head=${head} failed-sequence=1 code=insufficient_quota verdict=none artifact=none replacement=none`
 let paused=0
 const x={readPaidReviewStarts:()=>[{...row(),commit:{message:message()}}],getCommit:()=>({message:release,committedDate:'2026-10-06T18:00:00Z'}),pauseReviewerFailure:r=>{assert.deepEqual(r,{...record,observedEpoch:1791309600});paused++}}
 assert.equal(pauseActualReviewFailure(record,x).paused,true);assert.equal(paused,1)
 assert.equal(pauseActualReviewFailure({...record,failureCode:'local_dependency_unavailable'},x).paused,false)
 assert.equal(pauseActualReviewFailure({...record,failureCode:'wrapper_terminal_failure'},x).paused,false)
 assert.equal(pauseActualReviewFailure({...record,failedSequence:2},x).paused,false)
 assert.throws(()=>pauseActualReviewFailure(record,{...x,getCommit:()=>({message:release.replace('head='+head,'head='+next)})}),/binding mismatch/)
})

test('inline replacement pauses actual failed provider using immutable self failure',()=>{
 const record={...request,failedSequence:1,failureCode:'provider_unavailable',failureSha:'f'.repeat(40)}
 const failure=`db-coordination reviewer-failure-replacement sequence=2 reviewer=muse-spark-1.3-contributor issue=3536 pr=4000 head=${head} slot=1 failed-sequence=1 prior-sequence=1 failure-ref=self failed-reviewer=glm-5.3 code=provider_unavailable verdict=none artifact=none`
 let paused=0
 const x={readPaidReviewStarts:()=>[{...row(),commit:{message:message()}}],readReviewFailureCommit:()=>({message:failure,committedDate:'2026-10-06T18:00:00Z'}),getCommit:()=>{throw Error('wire read forbidden')},pauseReviewerFailure:r=>{assert.equal(r.reviewer,'glm-5.3');paused++}}
 assert.equal(pauseActualReviewFailure(record,x).paused,true);assert.equal(paused,1)
})

test('all historical substantive comparisons share one operation base context',()=>{
 const x=io([row(),row(2)]);let shared,calls=0
 x.reviewContentComparison=(before,after,pr,context)=>{calls++;if(shared)assert.equal(context,shared);else shared=context;return{before:digest,after:'d'.repeat(64),budgetProof:{schema:1,before:head,after:next,protectedMain:head,kind:'substantive',historyCount:1}}}
 assert.equal(assertPaidReviewCapacity({...request,headSha:next},x).remaining,2);assert.equal(calls,2)
})

test('provider pause refuses unknown immutable timestamp and reports expired original window honestly',()=>{
 const record={...request,failedSequence:1,failureCode:'provider_unavailable',failureSha:'f'.repeat(40)}
 const messageFailure=`db-coordination reviewer-failure-release reviewer=glm-5.3 issue=3536 pr=4000 head=${head} failed-sequence=1 code=provider_unavailable verdict=none artifact=none replacement=none`
 const x={readPaidReviewStarts:()=>[{...row(),commit:{message:message()}}],readReviewFailureCommit:()=>({message:messageFailure}),pauseReviewerFailure:()=>assert.fail('unknown timestamp must never invoke public pause')}
 assert.throws(()=>pauseActualReviewFailure(record,x),/timestamp unreadable/)
 x.readReviewFailureCommit=()=>({message:messageFailure,committedDate:'2026-10-06T18:00:00Z'})
 x.pauseReviewerFailure=r=>{assert.equal(r.observedEpoch,1791309600);return{status:'expired',provider:'glm',observed_epoch:r.observedEpoch,expires_epoch:r.observedEpoch+3600}}
 const result=pauseActualReviewFailure(record,x);assert.equal(result.paused,false);assert.equal(result.reason,'original failure window expired')
})

test('exact row ceiling and malformed PR cannot be accepted as complete paid history',()=>{
 assert.throws(()=>assertPaidReviewCapacity(request,io(Array.from({length:1000},()=>row()))),/may be truncated/)
 for(const pr of [NaN,'4000',0,-1])assert.throws(()=>assertPaidReviewCapacity({...request,pr},io([])),/exact positive PR/)
})

import {execFileSync} from 'node:child_process'
import {mkdtempSync,writeFileSync,rmSync,mkdirSync} from 'node:fs'
import {tmpdir} from 'node:os'
import path from 'node:path'
function realGitFixture(t) {
 const dir=mkdtempSync(path.join(tmpdir(),'review-budget-git-'));t.after(()=>rmSync(dir,{recursive:true,force:true}))
 const git=args=>execFileSync('git',args,{cwd:dir,encoding:'utf8',stdio:['ignore','pipe','pipe']})
 git(['init','-q','-b','main']);git(['config','user.name','Fixture']);git(['config','user.email','fixture@example.test'])
 const commit=(file,text)=>{writeFileSync(path.join(dir,file),text);git(['add',file]);git(['commit','-qm','fixture']);return git(['rev-parse','HEAD']).trim()}
 const base=commit('app.txt','context\nseparator1\nseparator2\nauthor\nend\n');git(['switch','-qc','feature'])
 const before=commit('app.txt','context\nseparator1\nseparator2\nfixed\nend\n')
 return {git,commit,base,before,dir}
}
test('real Git main-context merge retains two spent attempts despite changed review context',t=>{
 const f=realGitFixture(t);f.git(['switch','main']);const main=f.commit('app.txt','new context\nseparator1\nseparator2\nauthor\nend\n')
 f.git(['switch','feature']);f.git(['merge','-qm','main refresh','main']);const after=f.git(['rev-parse','HEAD']).trim()
 const proof=derivePaidContentProof(f.before,after,main,f.git)
 assert.equal(proof.kind,'unchanged')
 const rows=[1,2].map(n=>({...row(n,f.before),commit:{message:message(n,f.before)}}))
 assert.throws(()=>assertPaidReviewCapacity({...request,headSha:after},{listRefs:()=>rows,reviewContentComparison:()=>({before:digest,after:'d'.repeat(64),budgetProof:proof})}),/third draw refused/)
})
test('real Git genuine author fix resets while net revert and empty commits retain budget',t=>{
 const f=realGitFixture(t);const changed=f.commit('app.txt','context\nrepaired\nend\n')
 assert.equal(derivePaidContentProof(f.before,changed,f.base,f.git).kind,'substantive')
 const reverted=f.commit('app.txt','context\nseparator1\nseparator2\nfixed\nend\n')
 assert.equal(derivePaidContentProof(f.before,reverted,f.base,f.git).kind,'unchanged')
 f.git(['commit','--allow-empty','-qm','empty']);assert.equal(derivePaidContentProof(f.before,f.git(['rev-parse','HEAD']).trim(),f.base,f.git).kind,'unchanged')
})
test('real Git foreign feature merge and rewritten differing history refuse reset',t=>{
 const f=realGitFixture(t);f.git(['switch','-qc','foreign',f.base]);f.commit('foreign.txt','foreign source')
 f.git(['switch','feature']);f.git(['merge','-qm','foreign merge','foreign']);const after=f.git(['rev-parse','HEAD']).trim()
 assert.throws(()=>derivePaidContentProof(f.before,after,f.base,f.git),/foreign merge/)
 f.git(['switch','-qc','rewritten',f.base]);const rewritten=f.commit('app.txt','context\nother fix\nend\n')
 assert.throws(()=>derivePaidContentProof(f.before,rewritten,f.base,f.git),/provenance refused/)
})

test('real Git evidence-only changes retain count and missing proof cannot reset',t=>{
 const f=realGitFixture(t);const evidence=f.commit('evidence.json','evidence')
 assert.equal(derivePaidContentProof(f.before,evidence,f.base,f.git,['evidence.json']).kind,'unchanged')
 const x=io([row(),row(2)]);x.reviewContentComparison=()=>({before:digest,after:'d'.repeat(64),doctor:'PASS'})
 assert.throws(()=>assertPaidReviewCapacity({...request,headSha:next},x),/provenance proof unreadable/)
})
test('complete bounded history refuses the 1000 boundary',t=>{
 const f=realGitFixture(t);const changed=f.commit('app.txt','substantive')
 const git=args=>args[0]==='rev-list'&&args.includes('--max-count=1001')?Array.from({length:1001},(_,i)=>i===1000?f.before:changed).join('\n'):f.git(args)
 assert.throws(()=>derivePaidContentProof(f.before,changed,f.base,git),/complete first-parent ancestry/)
})

test('production public Git IO derives budget proof from a real clean main-only merge',t=>{
 const f=realGitFixture(t);f.git(['switch','main']);const main=f.commit('app.txt','new context\nseparator1\nseparator2\nauthor\nend\n')
 f.git(['switch','feature']);f.git(['merge','-qm','refresh','main']);const after=f.git(['rev-parse','HEAD']).trim()
 f.git(['remote','add','origin',f.dir])
 const moduleUrl=new URL('../../manage-migration-author-lanes.mjs',import.meta.url).href
 const script=`import {githubIo} from ${JSON.stringify(moduleUrl)};const p=githubIo.reviewContentComparison(${JSON.stringify(f.before)},${JSON.stringify(after)},4000,{base:${JSON.stringify(main)}});console.log(JSON.stringify(p))`
 const proof=JSON.parse(execFileSync(process.execPath,['--input-type=module','-e',script],{cwd:f.dir,encoding:'utf8',stdio:['ignore','pipe','pipe']}))
 assert.notEqual(proof.before,proof.after);assert.equal(proof.budgetProof.kind,'unchanged');assert.equal(proof.budgetProof.before,f.before);assert.equal(proof.budgetProof.after,after)
})

test('real Git source-equivalent rewrite preserves count while a custom merge refuses',t=>{
 const f=realGitFixture(t)
 f.git(['switch','-qc','equivalent',f.base]);const equivalent=f.commit('app.txt','context\nseparator1\nseparator2\nfixed\nend\n')
 assert.equal(derivePaidContentProof(f.before,equivalent,f.base,f.git).kind,'unchanged')
 f.git(['switch','main']);const main=f.commit('main-only.txt','main offset')
 f.git(['switch','feature']);f.git(['merge','--no-commit','main']);writeFileSync(path.join(f.dir,'custom.txt'),'custom merge source');f.git(['add','custom.txt']);f.git(['commit','-qm','custom merge'])
 const after=f.git(['rev-parse','HEAD']).trim()
 assert.throws(()=>derivePaidContentProof(f.before,after,main,f.git),/noncanonical/)
})
test('real Git offset-only main merge preserves count, but conflicting main ancestry refuses',t=>{
 const f=realGitFixture(t);f.git(['switch','main']);const main=f.commit('app.txt','inserted\ncontext\nseparator1\nseparator2\nauthor\nend\n')
 f.git(['switch','feature']);f.git(['merge','-qm','offset refresh','main']);const after=f.git(['rev-parse','HEAD']).trim()
 assert.equal(derivePaidContentProof(f.before,after,main,f.git).kind,'unchanged')
 f.git(['switch','main']);const conflict=f.commit('app.txt','inserted\ncontext\nseparator1\nseparator2\nmain conflicting edit\nend\n')
 f.git(['switch','feature']);assert.throws(()=>f.git(['merge','--no-commit','main']))
 writeFileSync(path.join(f.dir,'app.txt'),'manual conflicting resolution');f.git(['add','app.txt']);f.git(['commit','-qm','resolved conflict']);const resolved=f.git(['rev-parse','HEAD']).trim()
 assert.throws(()=>derivePaidContentProof(f.before,resolved,conflict,f.git),/provenance refused/)
})

function appendFixture(t,{repair=false,revert=false,reordered=false,omit=false,mode=false,oldLine=false}={}) {
 const dir=mkdtempSync(path.join(tmpdir(),'review-budget-append-real-'));t.after(()=>rmSync(dir,{recursive:true,force:true}))
 const git=args=>execFileSync('git',args,{cwd:dir,encoding:'utf8',stdio:['ignore','pipe','pipe']})
 git(['init','-q','-b','main']);git(['config','user.name','Fixture']);git(['config','user.email','fixture@example.test'])
 git(['config','core.fileMode','false'])
 const file='scripts/manage-migration-author-lanes.test.mjs';mkdirSync(path.join(dir,'scripts'))
 const base='// protected baseline\n',ours="test('author append',()=>{});\n",theirs="test('main append',()=>{});\n"
 let modePending=false
 const commit=()=>{git(['add','.']);if(modePending){git(['update-index','--chmod=+x',file]);modePending=false}git(['commit','-qm','fixture']);return git(['rev-parse','HEAD']).trim()}
 writeFileSync(path.join(dir,file),base);writeFileSync(path.join(dir,'app.txt'),'base source');commit()
 git(['switch','-qc','feature']);writeFileSync(path.join(dir,file),(oldLine?'// author old-line edit\n':base)+ours);writeFileSync(path.join(dir,'app.txt'),'implementation');const before=commit()
 if(repair){writeFileSync(path.join(dir,'app.txt'),'repaired source');commit()}
 if(revert){writeFileSync(path.join(dir,'app.txt'),'implementation');commit()}
 git(['switch','main']);writeFileSync(path.join(dir,file),(oldLine?'// main old-line edit\n':base)+theirs);modePending=mode;const main=commit()
 git(['switch','feature']);assert.throws(()=>git(['merge','--no-commit','main']))
 writeFileSync(path.join(dir,file),base+(reordered?theirs+ours:omit?ours:ours+theirs));const after=commit()
 return {git,before,after,main,file,dir}
}
test('canonical independent EOF test appends cannot reset two spent attempts',t=>{
 const f=appendFixture(t),proof=derivePaidContentProof(f.before,f.after,f.main,f.git)
 assert.equal(proof.kind,'unchanged');assert.equal(proof.canonicalAppends.length,1)
 const rows=[1,2].map(n=>({...row(n,f.before),commit:{message:message(n,f.before)}}))
 assert.throws(()=>assertPaidReviewCapacity({...request,headSha:f.after},{listRefs:()=>rows,reviewContentComparison:()=>({before:digest,after:'d'.repeat(64),budgetProof:proof})}),/third draw refused/)
})
test('canonical test reconciliation permits only a surviving conflict-free author source fix',t=>{
 const f=appendFixture(t,{repair:true}),proof=derivePaidContentProof(f.before,f.after,f.main,f.git)
 assert.equal(proof.kind,'substantive');assert.equal(proof.witness.path,'app.txt');assert.equal(proof.canonicalAppends.length,2)
})
test('canonical appends plus net reverted author fix preserve count',t=>{
 const f=appendFixture(t,{repair:true,revert:true});assert.equal(derivePaidContentProof(f.before,f.after,f.main,f.git).kind,'unchanged')
})
test('reordered, omitted, old-line and mode-changing test conflict resolutions refuse',t=>{
 for(const option of ['reordered','omit','oldLine','mode']) {
  const f=appendFixture(t,{repair:true,[option]:true})
  assert.throws(()=>derivePaidContentProof(f.before,f.after,f.main,f.git),/provenance refused/,option)
 }
})

test('production public Git IO reconciles exact test appends with surviving source witness',t=>{
 const f=appendFixture(t,{repair:true});f.git(['remote','add','origin',f.dir])
 const moduleUrl=new URL('../../manage-migration-author-lanes.mjs',import.meta.url).href
 const script=`import {githubIo} from ${JSON.stringify(moduleUrl)};console.log(JSON.stringify(githubIo.reviewContentComparison(${JSON.stringify(f.before)},${JSON.stringify(f.after)},4000,{base:${JSON.stringify(f.main)}})))`
 const proof=JSON.parse(execFileSync(process.execPath,['--input-type=module','-e',script],{cwd:f.dir,encoding:'utf8',stdio:['ignore','pipe','pipe']}))
 assert.equal(proof.budgetProof.kind,'substantive');assert.equal(proof.budgetProof.witness.path,'app.txt')
 for(const r of proof.budgetProof.canonicalAppends){assert.equal(r.path,f.file);assert.match(r.base,/^[0-9a-f]{40}$/);assert.equal(r.parents.length,2);assert.equal(r.parentBlobs.length,3);assert.match(r.canonicalBlob,/^[0-9a-f]{40}$/)}
})
test('custom attributes and ambiguous marker bytes cannot reconcile a test conflict',t=>{
 const f=appendFixture(t,{repair:true})
 for(const attribute of ['merge=custom','filter=custom','working-tree-encoding=UTF-16']) {
  writeFileSync(path.join(f.dir,'.gitattributes'),`${f.file} ${attribute}\n`)
  assert.throws(()=>derivePaidContentProof(f.before,f.after,f.main,f.git),/custom merge/)
 }
 rmSync(path.join(f.dir,'.gitattributes'))
 const bad=args=>args[0]==='show'&&String(args[1]).endsWith(':'+f.file)?f.git(args)+'<<<<<<< forged marker\n':f.git(args)
 assert.throws(()=>derivePaidContentProof(f.before,f.after,f.main,bad),/blob bytes unreadable/)
})

test('octopus and wrong protected-main provenance cannot authorize append repair',t=>{
 const f=appendFixture(t,{repair:true});const tree=f.git(['rev-parse',`${f.after}^{tree}`]).trim()
 f.git(['switch','-qc','foreign',f.before]);writeFileSync(path.join(f.dir,'foreign.txt'),'foreign');f.git(['add','foreign.txt']);f.git(['commit','-qm','foreign']);const foreign=f.git(['rev-parse','HEAD']).trim()
 const octopus=f.git(['commit-tree',tree,'-p',f.before,'-p',f.main,'-p',foreign,'-m','octopus']).trim()
 assert.throws(()=>derivePaidContentProof(f.before,octopus,f.main,f.git),/ambiguous merge/)
 assert.throws(()=>derivePaidContentProof(f.before,f.after,f.before,f.git),/foreign merge/)
})

test('ordinary conflict-free test-only author fixes retain mandatory fresh review capability',t=>{
 const f=realGitFixture(t);mkdirSync(path.join(f.dir,'scripts'));const file='scripts/manage-migration-author-lanes.test.mjs'
 const after=f.commit(file,"test('new authored regression',()=>{});\n")
 const proof=derivePaidContentProof(f.before,after,f.base,f.git)
 assert.equal(proof.kind,'substantive');assert.equal(proof.witness.path,file);assert.equal(proof.canonicalAppends.length,0)
})

test('actual Git link metadata and renamed test conflict ancestry refuse reconciliation',t=>{
 for(const kind of ['link','rename']) {
  const f=appendFixture(t,{repair:true});f.git(['read-tree',f.main])
  if(kind==='link') {
   const target=path.join(f.dir,'target-bytes');writeFileSync(target,'app.txt');const blob=f.git(['hash-object','-w',target]).trim()
   f.git(['update-index','--add','--cacheinfo',`120000,${blob},${f.file}`])
  } else {
   const blob=f.git(['rev-parse',`${f.main}:${f.file}`]).trim();f.git(['update-index','--force-remove',f.file]);f.git(['update-index','--add','--cacheinfo',`100644,${blob},scripts/renamed.test.mjs`])
  }
  const changedTree=f.git(['write-tree']).trim(),changedMain=f.git(['commit-tree',changedTree,'-p',f.main,'-m',kind]).trim()
  const actualTree=f.git(['rev-parse',`${f.after}^{tree}`]).trim(),after=f.git(['commit-tree',actualTree,'-p',f.after,'-p',changedMain,'-m','unexplained resolution']).trim()
  assert.throws(()=>derivePaidContentProof(f.before,after,changedMain,f.git),/provenance refused/,kind)
 }
})
