import test from 'node:test'
import assert from 'node:assert/strict'
import {createHash} from 'node:crypto'
import {canonicalJson} from '../db-flow/evidence-bundle.mjs'
import {proposeTrain,trainRecordRef} from '../db-flow/migration-train.mjs'
import {findingsDigest} from './review-verdict-artifact.mjs'
import {loadTrainTargetEvidence,trainTargetRequest,parseTrainTargetAssessment,proveTrainTargetAssessment,publishTrainTargetAssessment,trainTargetIndex,TRAIN_TARGET_CONTRACT_FILES,TRAIN_TARGET_SCHEMA} from './production-train-target-assessment.mjs'
const h=(c,n=40)=>c.repeat(n),hash=s=>createHash('sha256').update(s).digest('hex'),MAIN=h('a'),ANCHOR=h('b'),PR=5000,ISSUE=4655,WORK=3869
const versions=['20261022221940','20261023014911'],risk=['material_access_change']
const explanation='The exact sealed policy and mutation assertions bound this change; unrelated backend drift remains excluded.'
function fixture(){
 const files=new Map(),refs=new Map(),commits=new Map(),prs=new Map(),prfiles=new Map(),findings=new Map()
 const sources=[4648,4673], heads=[h('c'),h('d')],merges=[h('e'),h('f')]
 const paths=versions.map((v,i)=>`supabase/migrations/${v}_tracking_${i}.sql`)
 const entries=versions.map((version,i)=>{const body=`-- immutable synthetic source ${i}\nselect ${i};\n`;for(const sha of [MAIN,heads[i]])files.set(`${sha}:${paths[i]}`,body);prs.set(sources[i],{number:sources[i],merged:true,merged_at:'2026-10-23',head:{sha:heads[i]},merge_commit_sha:merges[i]});prfiles.set(sources[i],[{filename:paths[i],status:'added'}]);return{version,file_sha256:hash(body),source_pr:sources[i],merge_sha:merges[i],dependencies:i?[versions[0]]:[],risk_class:'ddl-compatible',role:'postgres',preview_assertion:'exact preview',production_assertion:'exact production'}})
 const proposed=proposeTrain({target:'production',target_identity:'supabase:qsllyeztdwjgirsysgai',base_main_sha:MAIN,entries}), train={...proposed,state:'dispatched',generation:3},trainRef=trainRecordRef(train),trainSha=h('1')
 refs.set(trainRef,trainSha);commits.set(trainSha,{message:`db-migration-train ${JSON.stringify({digest:hash(canonicalJson(train)),record:train})}`})
 prs.set(PR,{number:PR,merged:true,merged_at:'2026-10-24',head:{sha:ANCHOR}})
 const contract='.agent/work/4655/30/contract.json';prfiles.set(PR,[{filename:'scripts/lib/production-train-target-assessment.mjs',status:'added'},{filename:contract,status:'added'}]);files.set(`${ANCHOR}:${contract}`,JSON.stringify({work_issue:ISSUE,work_type:'repo-maintenance',route:'repo-maintenance',db_reads:[],db_writes:[]}))
 for(const path of TRAIN_TARGET_CONTRACT_FILES)files.set(`${MAIN}:${path}`,path==='config/designflow-db-releases.json'?JSON.stringify({production_project_ref:'qsllyeztdwjgirsysgai'}):`-- current contract ${path}\n`)
 const refusalRef=`refs/db-review-verdicts/${WORK}-${sources[0]}-${heads[0]}`,assignmentRef=`refs/db-review-assignments/${WORK}-${sources[0]}-${heads[0]}`
 const assignmentSha=h('2'),refusalSha=h('3'),findingRef=`https://github.com/popcre/shared-db/pull/${sources[0]}#issuecomment-1`,body='Canonical independent refusal: contract and inherited backend exposure require a separately proved amendment.'
 const record={verdict:'REJECT',head_sha:heads[0],issue:WORK,pr:sources[0],slot:1,reviewer:'muse-spark-1.3-contributor',assignment_sha:assignmentSha,findings_ref:findingRef,findings_digest:findingsDigest(body)}
 refs.set(assignmentRef,assignmentSha);refs.set(refusalRef,refusalSha)
 commits.set(assignmentSha,{message:`db-coordination reviewer-cursor sequence=1 reviewer=muse-spark-1.3-contributor issue=${WORK} pr=${sources[0]} head=${heads[0]} slot=1`})
 commits.set(refusalSha,{message:`db-review-verdict ${JSON.stringify(record)}`,parents:[{sha:assignmentSha}]});findings.set(findingRef,body)
 let main=MAIN
 const io={mainSha:()=>main,readRef:ref=>refs.get(ref)??null,listRefs:prefix=>[...refs].filter(([ref])=>ref.startsWith(prefix)).map(([ref,sha])=>({ref,sha})),getCommit:sha=>commits.get(sha),getPr:n=>prs.get(n),getPrFiles:n=>prfiles.get(n),closingIssuesForPr:()=>[{number:WORK}],getIssue:()=>({state:'open'}),compareCommits:()=>({status:'ahead',behind_by:0}),getFileAt:(path,sha)=>files.get(`${sha}:${path}`),readFindings:ref=>findings.get(ref),createRef:(ref,sha)=>{if(refs.has(ref))return false;refs.set(ref,sha);return true}}
 const opts={mainSha:MAIN,trainRef,allowlist:versions,assessmentPr:PR,assessmentHead:ANCHOR,issue:ISSUE,risks:risk}
 return{io,opts,files,refs,commits,prs,prfiles,findings,train,trainRef,refusalRef,setMain:sha=>{main=sha}}
}
function assessment(binding){return{...structuredClone(binding),assessedRisks:{material_access_change:explanation},findings:Object.fromEntries(['B1','B2','B3','B4','B5'].map(k=>[k,{conclusion:'resolved',evidence:`${k}: ${explanation}`}]))}}
const body=data=>`Independent findings\n\`\`\`production-train-target-assessment\n${JSON.stringify(data)}\n\`\`\`\n`

test('packet seals both exact SQLs, all current contract bytes and authenticated immutable refusals',()=>{
 const f=fixture(),e=loadTrainTargetEvidence(f.opts,f.io)
 assert.equal(e.binding.sources.length,2);assert.equal(e.binding.priorRefusals.length,1);assert.equal(e.binding.priorRefusals[0].verdict,'REJECT')
 assert.equal(e.files.length,2+TRAIN_TARGET_CONTRACT_FILES.length)
 const request=trainTargetRequest(e,risk)
 assert.match(request,/Canonical independent refusal/);assert.match(request,/current contract/);assert.match(request,/immutable synthetic source 0/);assert.match(request,/immutable synthetic source 1/)
 assert.ok(request.includes(e.binding.bindingDigest));assert.equal(e.binding.targetIdentity,'supabase:qsllyeztdwjgirsysgai')
})

test('packet refuses stale main, wrong target, nonlatest train, changed SQL, unmerged source, foreign anchor and omitted refusal findings',()=>{
 const mutations=[
 f=>f.setMain(h('9')),
 f=>f.opts.allowlist=[...versions].reverse(),
 f=>f.io.compareCommits=()=>({status:'behind',behind_by:1}),
 f=>f.files.set(`${MAIN}:supabase/migrations/${versions[0]}_tracking_0.sql`,'changed source'),
 f=>f.prs.get(4648).merged=false,
 f=>f.prfiles.set(PR,[]),
 f=>f.io.closingIssuesForPr=n=>[{number:n}],
 f=>f.io.getIssue=()=>({state:'closed'}),
 f=>f.findings.clear(),
 f=>f.files.set(`${MAIN}:config/designflow-db-releases.json`,JSON.stringify({production_project_ref:'aaaaaaaaaaaaaaaaaaaa'})),
 f=>f.refs.set(f.trainRef.replace('000003-dispatched','000004-closed'),h('9')),
 f=>f.files.delete(`${MAIN}:scripts/proofs/2873-catalog.sql`)
 ]
 for(const mutate of mutations){const f=fixture();mutate(f);assert.throws(()=>loadTrainTargetEvidence(f.opts,f.io))}
})

test('historical refusal omission is detected even when archived; findings edits are never accepted',()=>{
 const f=fixture(),sha=f.refs.get(f.refusalRef)
 f.refs.delete(f.refusalRef);f.refs.set(`refs/db-review-archived-verdicts/${f.refusalRef.slice(5)}`,sha)
 const e=loadTrainTargetEvidence(f.opts,f.io)
 assert.equal(e.binding.priorRefusals[0].ref,f.refusalRef)
 f.findings.set([...f.findings.keys()][0],'rewritten refusal')
 assert.throws(()=>loadTrainTargetEvidence(f.opts,f.io),/digest/)
})

test('assessment validates exact live train, source, contract and refusal inventory plus every B1–B5 conclusion',()=>{
 const f=fixture(),e=loadTrainTargetEvidence(f.opts,f.io),data=assessment(e.binding)
 assert.equal(parseTrainTargetAssessment(body(data),e.binding,risk).schema,TRAIN_TARGET_SCHEMA)
 const mutations=[d=>d.mainSha=h('9'),d=>d.target='preview',d=>d.targetIdentity='other',d=>d.trainRef+='wrong',d=>d.trainDigest=h('9',64),d=>d.orderedAllowlist.reverse(),d=>d.sources[0].fileSha256=h('9',64),d=>d.sources[1].pr=1,d=>d.contractFiles.pop(),d=>d.contractFiles[0].sha256=h('9',64),d=>d.priorRefusals=[],d=>d.priorRefusals[0].sha=h('9'),d=>d.findings.B1.conclusion='unresolved',d=>delete d.findings.B2,d=>d.findings.B3.evidence='author says fixed',d=>d.assessedRisks={},d=>d.assessedRisks.recovery_unproven=explanation,d=>d.extra='unknown']
 for(const mutate of mutations){const bad=structuredClone(data);mutate(bad);assert.throws(()=>parseTrainTargetAssessment(body(bad),e.binding,risk))}
 assert.throws(()=>parseTrainTargetAssessment(body(data)+body(data),e.binding,risk),/exactly one/)
 assert.throws(()=>parseTrainTargetAssessment(body(data),e.binding,['expected_downtime']),/coverage/)
})

test('native assessment requires independent durable APPROVE and exact digest; index is create-only and read back',()=>{
 const f=fixture(),e=loadTrainTargetEvidence(f.opts,f.io),text=body(assessment(e.binding)),url='https://github.com/popcre/shared-db/pull/5000#issuecomment-2'
 f.findings.set(url,text)
 const row={verdict:'APPROVE',head_sha:ANCHOR,ref:`refs/db-review-verdicts/${ISSUE}-${PR}-${ANCHOR}-slot2`,sha:h('4'),findings_ref:url,findings_digest:findingsDigest(text)}
 const deps={approval:()=>[row]}
 assert.throws(()=>proveTrainTargetAssessment(f.opts,f.io,deps),/published index/)
 const published=publishTrainTargetAssessment(f.opts,f.io,deps)
 assert.equal(f.refs.get(trainTargetIndex(e.binding)),row.sha)
 assert.equal(published.verdictSha,row.sha)
 assert.equal(publishTrainTargetAssessment(f.opts,f.io,deps).verdictSha,row.sha)
 assert.equal(proveTrainTargetAssessment(f.opts,f.io,deps).verdictSha,row.sha)
 f.commits.set(row.sha,{message:`db-review-verdict ${JSON.stringify({issue:ISSUE,pr:PR,head_sha:ANCHOR})}`})
 const {assessmentPr,assessmentHead,issue,...discover}=f.opts
 assert.equal(proveTrainTargetAssessment(discover,f.io,deps).verdictSha,row.sha)
 assert.throws(()=>proveTrainTargetAssessment(f.opts,f.io,{approval:()=>{throw new Error('durable reviewer refusal')}}),/refusal/)
 assert.throws(()=>proveTrainTargetAssessment(f.opts,f.io,{approval:()=>[{...row,verdict:'REJECT'}]}),/not exact-anchor/)
 f.refs.set(trainTargetIndex(e.binding),h('5'))
 assert.throws(()=>publishTrainTargetAssessment(f.opts,f.io,deps),/conflicting immutable/)
 f.refs.set(trainTargetIndex(e.binding),row.sha);f.findings.set(url,text+'changed')
 assert.throws(()=>proveTrainTargetAssessment(f.opts,f.io,deps),/digest changed/)
 assert.equal(f.refs.get(f.refusalRef),h('3'),'historical refusal never changed')
})
