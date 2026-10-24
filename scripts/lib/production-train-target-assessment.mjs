// A current-target judgement is distinct from historical source approval. Never
// call this from the generic exact-head merge guard or alter a source verdict.
import { createHash } from 'node:crypto'
import { githubIo, assertDurableReviewApproval, readReviewVerdicts, withArchivedVerdictMirror } from '../manage-migration-author-lanes.mjs'
import { readVerifiedTrainRecord } from '../db-flow/read-verified-train-record.mjs'
import { canonicalJson } from '../db-flow/evidence-bundle.mjs'
import { parseVerdictRef, parseVerdictCommit, findingsDigest } from './review-verdict-artifact.mjs'

export const TRAIN_TARGET_SCHEMA = 'shared-db-production-train-target-assessment/v2'
export const TRAIN_TARGET_INDEX = 'refs/db-train-target-assessments'
export const TRAIN_TARGET_CONTRACT_FILES = Object.freeze([
  'config/designflow-db-releases.json', 'scripts/proofs/2873-contract.json', 'scripts/proofs/2873-catalog.sql',
  'scripts/proofs/2873-role-contract.sql', 'scripts/proofs/shared-db-2873-observation.mjs',
  'scripts/proofs/shared-db-2873-observation.test.mjs'
])
const SHA = /^[0-9a-f]{40}$/, RISKS = ['expected_downtime','material_access_change','permanent_data_rewrite_or_loss']
const hash = text => createHash('sha256').update(text).digest('hex')
const same = (a,b) => canonicalJson(a) === canonicalJson(b)
const fail = message => { throw new Error(`train target assessment refused: ${message}`) }
function ancestry(io, base, main) {
  const result = io.compareCommits(base,main)
  if (!result || !['ahead','identical'].includes(result.status) || result.behind_by !== 0) fail('source or assessment anchor is not an ancestor of exact main')
}
function file(io,path,sha) {
  const body = io.getFileAt(path,sha)
  if (typeof body !== 'string' || !body.length || Buffer.byteLength(body)>512*1024) fail(`unreadable or oversized sealed file ${path}`)
  return {path,sha256:hash(body),body}
}
function allRefusals(issue,pr,io) {
  const mirror=withArchivedVerdictMirror(io), prefixes=['refs/db-review-verdicts','refs/db-review-verdict-replacements']
  const heads = new Set(prefixes.flatMap(prefix=>mirror.listRefs(`${prefix}/${issue}-${pr}-`)).map(row=>{
    const named=parseVerdictRef(row.ref)
    if (!named || named.issue!==issue || named.pr!==pr) fail('refusal inventory escaped source identity')
    return named.headSha
  }))
  return [...heads].flatMap(head=>readReviewVerdicts(issue,pr,head,mirror,{includeDisregarded:true}))
    .filter(row=>row.verdict!=='APPROVE').map(row=>{
      const body=io.readFindings(row.findings_ref)
      if(findingsDigest(body)!==row.findings_digest)fail('historical refusal findings changed')
      return {ref:row.ref,sha:row.sha,findingsRef:row.findings_ref,findingsDigest:row.findings_digest,verdict:row.verdict,body}
    }).sort((a,b)=>a.ref.localeCompare(b.ref))
}

// All bytes are loaded through the native tree reader at immutable SHAs; the
// caller cannot replace current contract authority with issue/comment prose.
export function loadTrainTargetEvidence({mainSha,trainRef,allowlist,assessmentPr,assessmentHead,issue},io=githubIo) {
  if(!SHA.test(mainSha??'')||!SHA.test(assessmentHead??'')||!Number.isSafeInteger(assessmentPr)||!Number.isSafeInteger(issue))fail('exact main and maintenance assessment anchor required')
  if(io.mainSha()!==mainSha)fail('current main moved')
  const versions=Array.isArray(allowlist)?allowlist:String(allowlist??'').split(',')
  const train=readVerifiedTrainRecord({ref:trainRef,target:'production',commitSha:mainSha,allowlist:versions.join(',')},io)
  if(!same(versions,train.entries.map(entry=>entry.version)))fail('ordered allowlist differs from exact train order')
  if(train.entries.length!==2||new Set(train.entries.map(e=>e.source_pr)).size!==2)fail('only an exact two-source production train is admitted')
  const anchor=io.getPr(assessmentPr)
  if(!anchor?.merged_at||anchor.merged!==true||anchor.head?.sha!==assessmentHead)fail('maintenance assessment anchor is not merged at the exact head')
  if(train.entries.some(e=>e.source_pr===assessmentPr))fail('assessment anchor cannot impersonate a historical authoring source')
  ancestry(io,assessmentHead,mainSha)
  const anchorFiles=io.getPrFiles(assessmentPr)
  if(!anchorFiles.some(e=>e.filename==='scripts/lib/production-train-target-assessment.mjs'))fail('assessment anchor does not author this capability')
  const contracts=anchorFiles.filter(e=>new RegExp(`^\\.agent/work/${issue}/[1-9][0-9]*/contract\\.json$`).test(e.filename))
  if(contracts.length!==1)fail('one maintenance contract on assessment anchor required')
  const maintenance=JSON.parse(io.getFileAt(contracts[0].filename,assessmentHead))
  if(maintenance.work_issue!==issue||maintenance.work_type!=='repo-maintenance'||maintenance.route!=='repo-maintenance'||!Array.isArray(maintenance.db_reads)||maintenance.db_reads.length||!Array.isArray(maintenance.db_writes)||maintenance.db_writes.length)fail('assessment anchor maintenance authority differs')
  let workIssue=null
  const sources=[],bodies=[],refusals=[]
  for(const entry of train.entries){
    const pr=io.getPr(entry.source_pr), linked=io.closingIssuesForPr(entry.source_pr)
    if(!pr?.merged_at||pr.merged!==true||!SHA.test(pr.head?.sha??'')||pr.merge_commit_sha!==entry.merge_sha)fail('historical source identity changed')
    if(!Array.isArray(linked)||linked.length!==1||!Number.isSafeInteger(linked[0].number))fail('source needs one shared structural issue')
    if(workIssue!==null&&workIssue!==linked[0].number)fail('sources bind different work issues')
    workIssue=linked[0].number
    if(io.getIssue(workIssue)?.state!=='open')fail('structural work issue must remain open')
    ancestry(io,entry.merge_sha,mainSha);ancestry(io,pr.head.sha,mainSha)
    const files=io.getPrFiles(entry.source_pr).filter(e=>e.status==='added'&&new RegExp(`^supabase/migrations/${entry.version}_[A-Za-z0-9._-]+\\.sql$`).test(e.filename))
    if(files.length!==1)fail('source must author exactly the selected migration')
    const path=files[0].filename, atHead=file(io,path,pr.head.sha), atMain=file(io,path,mainSha)
    if(atHead.sha256!==entry.file_sha256||atMain.sha256!==entry.file_sha256)fail('historical and current-main SQL bytes differ from train')
    sources.push({version:entry.version,pr:entry.source_pr,headSha:pr.head.sha,mergeSha:entry.merge_sha,path,fileSha256:entry.file_sha256})
    bodies.push(atMain)
    refusals.push(...allRefusals(workIssue,entry.source_pr,io))
  }
  const contractBodies=TRAIN_TARGET_CONTRACT_FILES.map(path=>file(io,path,mainSha))
  const project=JSON.parse(contractBodies.find(f=>f.path==='config/designflow-db-releases.json').body).production_project_ref
  if(!/^[a-z]{20}$/.test(project??'')||train.target_identity!==`supabase:${project}`)fail('train target identity differs from canonical production project')
  const priorRefusals=refusals.sort((a,b)=>a.ref.localeCompare(b.ref)).map(({body,...identity})=>identity)
  if(!priorRefusals.length)fail('target reassessment requires preserved historical refusals')
  const binding={schema:TRAIN_TARGET_SCHEMA,mainSha,target:'production',targetIdentity:train.target_identity,trainRef,trainId:train.train_id,trainDigest:hash(canonicalJson(train)),orderedAllowlist:versions,sources,sourcePrMap:Object.fromEntries(sources.map(s=>[s.version,s.pr])),contractFiles:contractBodies.map(({body,...identity})=>identity),priorRefusals,assessmentPr,assessmentHead,maintenanceIssue:issue,workIssue}
  binding.bindingDigest=hash(canonicalJson(binding))
  if(io.mainSha()!==mainSha)fail('current main moved during packet creation')
  return {binding,files:[...bodies,...contractBodies],refusals}
}

export function trainTargetRequest(evidence,risks) {
  const wanted=[...new Set(String(risks??'').split(',').filter(Boolean))].sort()
  if(!wanted.length||wanted.some(r=>!RISKS.includes(r)))fail('exact derived risk classes required')
  const skeleton={...evidence.binding,assessedRisks:Object.fromEntries(wanted.map(r=>[r,'<independent substantive assessment>'])),findings:Object.fromEntries(['B1','B2','B3','B4','B5'].map(k=>[k,{conclusion:'<resolved or not-applicable with source-backed reason>',evidence:'<exact sealed source reference and substantive reasoning>'}]))}
  const text=`## Runner-sealed current-target assessment, distinct from historical source approval\n\nThe native runner proved the exact latest DISPATCHED production train, both source SQLs and the CURRENT main permission contract below. These bytes, not author comments or the historical anchor checkout, are the target of this separate assessment. Preserve every historical refusal. Do not approve if any prior objection remains unresolved. Evaluate B1 contract/matrix; B2 inherited backend raw-history access; B3 schema USAGE assertions; B4 idempotent policy/recovery; B5 exact object kind/type/view shape. Read every complete prior finding below including additional findings beyond B1–B5. Explain each conclusion independently, with exact sealed file paths and source evidence. All SQL-derived risk classes must be substantively assessed; live proof remains a separate mandatory gate. Never accept unresolved objections, recovery uncertainty, unrelated backend drift, broader credentials or new SQL by this assessment.\n\nIf and only if acceptable, include exactly ONE fenced production-train-target-assessment JSON block matching this identity and replacing every placeholder. Otherwise REVISE/REJECT. This requests no change to source-head verdicts.\n\n${JSON.stringify(skeleton,null,2)}\n\n## Complete immutable target source bytes\n${evidence.files.map(f=>`### ${f.path} sha256:${f.sha256}\n${JSON.stringify(f.body)}`).join('\n\n')}\n\n## Complete authenticated historical refusals\n${evidence.refusals.map(r=>`${JSON.stringify(r)}`).join('\n\n')}`
  if(Buffer.byteLength(text)>1024*1024)fail('target packet exceeds bounded size; nothing was truncated')
  return text
}

export function parseTrainTargetAssessment(body,binding,risks=[]) {
  const blocks=[...String(body).matchAll(/```production-train-target-assessment[ \t]*\r?\n([\s\S]*?)\r?\n[ \t]*```/g)]
  if(blocks.length!==1)fail('exactly one target assessment block required')
  let data;try{data=JSON.parse(blocks[0][1])}catch{fail('target assessment JSON malformed')}
  const keys=[...Object.keys(binding),'assessedRisks','findings'].sort()
  if(!data||!same(Object.keys(data).sort(),keys))fail('target assessment fields differ')
  for(const key of Object.keys(binding))if(!same(data[key],binding[key]))fail(`target assessment ${key} differs from live proof`)
  const wanted=[...new Set(risks)].sort(), assessed=Object.keys(data.assessedRisks??{}).sort()
  if(!assessed.length||assessed.some(r=>!RISKS.includes(r))||(wanted.length&&!same(assessed,wanted)))fail('derived risk coverage differs')
  for(const r of assessed)if(typeof data.assessedRisks[r]!=='string'||data.assessedRisks[r].trim().length<40||/^<.*>$/.test(data.assessedRisks[r].trim()))fail('substantive risk assessment missing')
  if(!same(Object.keys(data.findings??{}).sort(),['B1','B2','B3','B4','B5']))fail('B1–B5 finding coverage missing')
  const sealedPaths=[...binding.sources.map(source=>source.path),...binding.contractFiles.map(file=>file.path)]
  for(const f of Object.values(data.findings))if(!f||!same(Object.keys(f).sort(),['conclusion','evidence'])||typeof f.conclusion!=='string'||!['resolved','not-applicable'].includes(f.conclusion)||typeof f.evidence!=='string'||f.evidence.trim().length<40||/^<.*>$/.test(f.evidence.trim())||!sealedPaths.some(path=>f.evidence.includes(path)))fail('unresolved or unsupported prior objection')
  return data
}

export function trainTargetIndex(binding){return `${TRAIN_TARGET_INDEX}/${binding.trainId}/${binding.mainSha}`}

export function proveTrainTargetAssessment(options,io=githubIo,{load=loadTrainTargetEvidence,approval=assertDurableReviewApproval}={}) {
  let {assessmentPr,assessmentHead,issue}=options
  if(!assessmentPr){
    const train=readVerifiedTrainRecord({ref:options.trainRef,target:'production',commitSha:options.mainSha,allowlist:options.allowlist.join(',')},io)
    const sha=io.readRef(`${TRAIN_TARGET_INDEX}/${train.train_id}/${options.mainSha}`)
    if(!SHA.test(sha??''))fail('no published target assessment for exact train/main')
    const meta=parseVerdictCommit(io.getCommit(sha))
    assessmentPr=meta.pr;assessmentHead=meta.head_sha;issue=meta.issue
  }
  const {binding}=load({...options,assessmentPr,assessmentHead,issue},io)
  const approved=approval(issue,assessmentPr,assessmentHead,io,{includeArchived:true})
  const failures=[]
  for(const verdict of approved){
    try{
      if(verdict.verdict!=='APPROVE'||verdict.head_sha!==assessmentHead)fail('assessment verdict is not exact-anchor APPROVE')
      const body=io.readFindings(verdict.findings_ref)
      if(findingsDigest(body)!==verdict.findings_digest)fail('assessment findings digest changed')
      const data=parseTrainTargetAssessment(body,binding,options.risks??[])
      const result={...binding,assessedRisks:data.assessedRisks,findings:data.findings,verdictRef:verdict.ref,verdictSha:verdict.sha,findingsRef:verdict.findings_ref,findingsDigest:verdict.findings_digest}
      if(!options.publish&&io.readRef(trainTargetIndex(binding))!==verdict.sha)fail('published index does not point to this approved verdict')
      return result
    }catch(error){failures.push(error.message)}
  }
  fail(`no independent current-target APPROVE: ${failures.join('; ')}`)
}

export function publishTrainTargetAssessment(options,io=githubIo,deps={}) {
  const proof=proveTrainTargetAssessment({...options,publish:true},io,deps),ref=trainTargetIndex(proof)
  const existing=io.readRef(ref)
  if(existing&&existing!==proof.verdictSha)fail('conflicting immutable target assessment already published')
  if(!existing)io.createRef(ref,proof.verdictSha)
  if(io.readRef(ref)!==proof.verdictSha)fail('target assessment index readback failed; do not replay uncertain publication')
  return {...proof,indexRef:ref}
}
