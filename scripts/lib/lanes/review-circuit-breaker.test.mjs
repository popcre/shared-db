import test from 'node:test'
import assert from 'node:assert/strict'
import { paidStart, assertPaidReviewCapacity, pauseActualReviewFailure } from './review-circuit-breaker.mjs'
const head='a'.repeat(40), next='b'.repeat(40), digest='c'.repeat(64)
const request={issue:3536,pr:4000,headSha:head,slot:1}
function row(seq=1,h=head,slot=1){return{ref:`refs/db-review-started/3536-4000-${h}-slot${slot}-seq${seq}`,sha:String(seq).padStart(40,'0')}}
function message(seq=1,h=head,slot=1){return`db-coordination review-started issue=3536 pr=4000 head=${h} slot=${slot} sequence=${seq} reviewer=glm-5.3 at=2026-10-06T18:00:00.000Z`}
function io(rows){return{listRefs:()=>rows,getCommit:sha=>({message:message(Number(sha))}),reviewContentComparison:()=>({before:digest,after:digest})}}
test('zero and one paid attempts retain capacity',()=>{assert.equal(assertPaidReviewCapacity(request,io([])).remaining,2);assert.equal(assertPaidReviewCapacity(request,io([row()])).remaining,1)})
test('third paid draw refuses unchanged exact head',()=>assert.throws(()=>assertPaidReviewCapacity(request,io([row(),row(2)])),/third draw refused/))
test('evidence-only or empty-head refresh cannot reset cap',()=>assert.throws(()=>assertPaidReviewCapacity({...request,headSha:next},io([row(),row(2)])),/third draw refused/))
test('substantive byte change starts another round',()=>{const x=io([row(),row(2)]);x.reviewContentComparison=()=>({before:digest,after:'d'.repeat(64)});assert.equal(assertPaidReviewCapacity({...request,headSha:next},x).remaining,2)})
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
 x.reviewContentComparison=(before,after,pr,context)=>{calls++;if(shared)assert.equal(context,shared);else shared=context;return{before:digest,after:'d'.repeat(64)}}
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
