// #4297: a completed decision without its source receipt is spent, never an approval.
import { createHash } from 'node:crypto'
import { openSync, closeSync, fstatSync, lstatSync, readFileSync, realpathSync, constants } from 'node:fs'
import { hostname, homedir } from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { parseStrictJson } from '../../proofs/shared-db-2870-observation.mjs'
import { resolveSessionAuthority } from '../session-authority.mjs'
import { contractHash, validateContract, validateCompletionReport, validatePullRequestCompletion, reconcileReportWithContract } from '../../agent-work-contract.mjs'
import { validateCompletionRecord } from '../work-dependencies.mjs'
import { sanitizePrDataEnv } from '../agent-evidence-paths.mjs'
import { verifyGitEvidence } from '../../agent-work-contract-git-evidence.mjs'
import { LaneError } from './claims.mjs'
import { reviewStartedMarkerRef, REVIEW_STARTED_REF_PREFIX, REVIEW_REF_ROW_LIMIT } from './constants.mjs'
import { lifecyclePoolReportBody } from '../../run-governed-review.mjs'
import { REVIEWERS } from './reviewer-roster.mjs'
import { archivedVerdictMirrorPrefix } from '../review-verdict-artifact.mjs'
import { paidStart } from './review-circuit-breaker.mjs'
import { parseReviewCursor, reviewLeaseRefForAssignment, parseReviewLease } from './review-records.mjs'

const sha = /^[0-9a-f]{40}$/, digest = /^[0-9a-f]{64}$/
const prefix = 'refs/db-review-dispositions'
const ownerPattern = /^Codex coordinator chat ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}) on ([A-Za-z0-9][A-Za-z0-9._-]{0,119})$/
const hash = bytes => createHash('sha256').update(bytes).digest('hex')
const fail = message => { throw new LaneError(`completed-unrecordable: ${message}`) }
const messageOf = commit => String(commit?.message ?? commit?.commit?.message ?? '')
const sameTuple = (a,b) => ['issue','pr','headSha','slot','sequence','reviewer'].every(k => a[k] === b[k])
export function dispositionIdentity(value) {
  const x = {issue:Number(value.issue),pr:Number(value.pr),headSha:String(value.headSha??''),slot:Number(value.slot??1),sequence:Number(value.sequence),reviewer:value.reviewer}
  if (![x.issue,x.pr,x.slot,x.sequence].every(n=>Number.isSafeInteger(n)&&n>0)||!sha.test(x.headSha)||x.reviewer!=='muse-spark-1.3-contributor') fail('exact Muse assignment tuple required')
  return x
}
export function completedUnrecordableRef(value) {
  // Readers support every original reviewer name, without admitting an execution provider.
  const x={...value,reviewer:'muse-spark-1.3-contributor'};const t=dispositionIdentity(x)
  return `${prefix}/${t.issue}-${t.pr}-${t.headSha}-slot${t.slot}-seq${t.sequence}`
}
export function parseCompletedUnrecordable(commit, expected) {
  const text=messageOf(commit), marker='db-coordination completed-unrecordable\n'
  if(!text.startsWith(marker))fail('disposition commit is malformed')
  let r;try{r=parseStrictJson(text.slice(marker.length))}catch{fail('disposition JSON is malformed')}
  const keys=['schema_version','kind','issue','pr','headSha','slot','sequence','reviewer','observed_verdict','authorizing','paid_attempt_consumed','human_identity_authenticated','declared_owner','machine','bindings','proof_sha256']
  if(Object.keys(r).sort().join()!==keys.sort().join()||r.schema_version!==1||r.kind!=='completed-unrecordable-missing-source-receipt'||r.authorizing!==false||r.paid_attempt_consumed!==true||r.human_identity_authenticated!==false||!['APPROVE','REVISE','REJECT'].includes(r.observed_verdict)||!digest.test(r.proof_sha256??''))fail('disposition is not a non-authorizing spent decision')
  dispositionIdentity(r)
  if(expected&&!sameTuple(r,expected))fail('disposition tuple mismatch')
  if(!Array.isArray(r.bindings)||r.bindings.length!==4||r.bindings.some(b=>Object.keys(b).sort().join()!=='ref,sha'||!sha.test(b.sha)||typeof b.ref!=='string'||!b.ref.startsWith('refs/')))fail('disposition source bindings are malformed')
  if(ownerPattern.exec(`Codex coordinator chat ${r.declared_owner} on ${r.machine}`)?.[0]!==`Codex coordinator chat ${r.declared_owner} on ${r.machine}`)fail('disposition owner is malformed')
  return r
}
export function readCompletedUnrecordable(value,io) {
  if(!sha.test(String(value.headSha??'')))return null // historical short-head protocol cannot name a disposition
  const ref=completedUnrecordableRef(value),snapshot=io.__completedDispositionSnapshot?.(value.issue,value.pr),cached=snapshot?.records.get(ref),listed=snapshot?.rows.filter(row=>row.ref===ref)
  if(snapshot&&((listed.length>0&&(!cached?.sha||listed.length!==1||cached.sha!==listed[0].sha))||(cached?.sha&&!listed.length)))fail('disposition snapshot is incomplete or changed')
  const s=snapshot?(cached?.sha??null):io.readRef(ref)
  if(s===null)return null
  if(!sha.test(s??''))fail('disposition ref unreadable')
  return {...parseCompletedUnrecordable(cached?.commit??io.getCommit(s),value),ref,sha:s}
}
export function assertReviewNotDisposed(value,io) {
  const r=readCompletedUnrecordable(value,io)
  if(r)fail('this completed paid attempt is disposed; continuation, reacquisition and recording are forbidden')
}
export function declaredDispositionOwner(dispatcher,{env=process.env,machine=hostname()}={}) {
  const m=typeof dispatcher==='string'&&ownerPattern.exec(dispatcher)
  if(!m||m[0]!==dispatcher||env.SHARED_DB_SESSION_ID!==m[1]||(env.CODEX_THREAD_ID!==undefined&&env.CODEX_THREAD_ID!==m[1])||machine!==m[2])fail('ownership-unproven')
  const authority=resolveSessionAuthority({env,claimOwner:m[1]})
  if(!authority.live||authority.task!==m[1])fail('ownership-unproven')
  return {declared_owner:m[1],machine:m[2],human_identity_authenticated:false}
}
export function protectedDispositionBytes(file,maxBytes=1048576) {
  let fd
  try {
    if(!path.isAbsolute(file)||realpathSync(file)!==path.resolve(file))throw Error('path')
    const before=lstatSync(file)
    if(!before.isFile()||before.nlink!==1||before.uid!==process.getuid()||(before.mode&0o077)!==0||before.size<1||before.size>maxBytes)throw Error('custody')
    fd=openSync(file,constants.O_RDONLY|(constants.O_NOFOLLOW??0));const first=fstatSync(fd),bytes=readFileSync(fd),after=fstatSync(fd),last=lstatSync(file)
    if(first.dev!==before.dev||first.ino!==before.ino||first.dev!==last.dev||first.ino!==last.ino||first.size!==after.size||first.mtimeMs!==after.mtimeMs||bytes.length!==first.size)throw Error('race')
    return {bytes,sha256:hash(bytes),path:file}
  } catch { fail('protected evidence is missing, changed, linked, unowned, oversized or not private') }
  finally {if(fd!==undefined)closeSync(fd)}
}
const privateJson = file => {const r=protectedDispositionBytes(file);try{return {...r,value:parseStrictJson(r.bytes.toString('utf8'))}}catch{fail('private evidence JSON is malformed')}}
function exactKeys(obj,keys,label) {if(!obj||typeof obj!=='object'||Array.isArray(obj)||Object.keys(obj).sort().join()!==[...keys].sort().join())fail(`${label} fields differ from the supported schema`)}
export function readCompletedDescriptor(file) {
  const r=privateJson(file),d=r.value
  exactKeys(d,['schema_version','contract_ref','source_root','receipt_path','lifecycle_file'],'descriptor')
  if(d.schema_version!==1||!/^refs\/db-contracts\/[1-9]\d*\/[1-9]\d*$/.test(d.contract_ref)||['source_root','receipt_path','lifecycle_file'].some(k=>typeof d[k]!=='string'||!path.isAbsolute(d[k])))fail('descriptor identity is malformed')
  return r
}
const gitContextNames=new Set(['GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR','GIT_INDEX_FILE','GIT_OBJECT_DIRECTORY','GIT_ALTERNATE_OBJECT_DIRECTORIES','GIT_NAMESPACE','GIT_CEILING_DIRECTORIES','GIT_DISCOVERY_ACROSS_FILESYSTEM','GIT_CONFIG','GIT_CONFIG_SYSTEM','GIT_CONFIG_GLOBAL','GIT_CONFIG_NOSYSTEM','GIT_CONFIG_PARAMETERS','GIT_REPLACE_REF_BASE','GIT_GRAFT_FILE','GIT_SHALLOW_FILE','GIT_EXEC_PATH'])
export function assertOriginalGitContext(env=process.env){
  for(const [key,value] of Object.entries(env))if(value&&((gitContextNames.has(key))||(key==='GIT_CONFIG_COUNT'&&value!=='0')||key.startsWith('GIT_CONFIG_KEY_')||key.startsWith('GIT_CONFIG_VALUE_')))fail('ambient Git context override refused before source qualification')
}
function sourceGit(root,args) {assertOriginalGitContext();try{return execFileSync('git',['--no-replace-objects','-c','core.hooksPath=/dev/null','-c','core.fsmonitor=false','-C',root,...args],{encoding:'utf8',timeout:30000,maxBuffer:4194304,stdio:['ignore','pipe','pipe'],env:sanitizePrDataEnv(process.env)})}catch{fail('original source Git evidence could not be verified')}}
function absentReceipt(file) {try{lstatSync(file);fail('reserved original receipt already exists')}catch(e){if(e?.code!=='ENOENT')throw e}}
// Native read-only packet commands, never provider dispatch or receipt publication.
function packet(args) {try{return execFileSync('ai-review-packet',args,{encoding:'utf8',timeout:30000,maxBuffer:1048576,stdio:['ignore','pipe','pipe'],env:{...process.env,AI_REVIEW_SOURCE_RECEIPT_FILE:''}})}catch{fail('native retained source packet verification refused')}}
export function qualifyCompletedUnrecordable(options,io,{env=process.env,machine=hostname(),git=sourceGit,packetRead=packet}={}) {
  assertOriginalGitContext(process.env);assertOriginalGitContext(env)
  const request=dispositionIdentity(options),pr=(io.__freshGetPr?.(request.pr)??io.getPr(request.pr))
  if(pr?.number!==request.pr||String(pr?.state).toLowerCase()!=='open'||pr?.head?.sha!==request.headSha||pr?.head?.repo?.full_name!=='popcre/shared-db'||pr?.base?.repo?.full_name!=='popcre/shared-db'||pr?.base?.ref!=='main'||!sha.test(pr?.base?.sha??''))fail('original PR must still be open at its original head')
  const descriptor=readCompletedDescriptor(options.completedUnrecordableEvidenceFile),d=descriptor.value
  let root;try{root=realpathSync(d.source_root)}catch{fail('original physical source is unavailable')}
  let top;try{top=git(root,['rev-parse','--show-toplevel']).trim();if(top!==root||realpathSync(top)!==root)fail('Git top-level differs from original physical source')}catch{fail('Git top-level differs from original physical source')}
  if(root!==d.source_root||git(root,['rev-parse','HEAD']).trim()!==request.headSha||git(root,['status','--porcelain','--untracked-files=normal']).trim())fail('original physical source is not clean at its original head')
  if(!/^((https:\/\/github.com\/popcre\/shared-db(?:\.git)?)|(git\x40github.com:popcre\/shared-db(?:\.git)?))$/.test(git(root,['remote','get-url','origin']).trim()))fail('original repository is not canonical shared-db')
  if(path.dirname(d.receipt_path)!==path.join(root,'.ai','reviews')||!/^governed-source-[0-9a-f-]{36}\.json$/.test(path.basename(d.receipt_path))||realpathSync(path.dirname(d.receipt_path))!==path.dirname(d.receipt_path))fail('reserved receipt is not its original physical destination')
  absentReceipt(d.receipt_path)
  const assignmentRef=`refs/db-review-assignments/${request.issue}-${request.pr}-${request.headSha}${request.slot===1?'':`-slot${request.slot}`}`
  const startRef=reviewStartedMarkerRef(request),leaseRef=reviewLeaseRefForAssignment(request,true),dispositionRef=completedUnrecordableRef(request)
  const refs=[d.contract_ref,assignmentRef,startRef,leaseRef,dispositionRef]
  const verdictPrefixes=['refs/db-review-verdicts','refs/db-review-verdict-replacements'].map(p=>`${p}/${request.issue}-${request.pr}-${request.headSha}`)
  const terminalPrefixes=[...verdictPrefixes,...verdictPrefixes.map(archivedVerdictMirrorPrefix),...['refs/db-review-failures','refs/db-review-replacements','refs/db-review-retired-verdicts'].map(p=>`${p}/${request.issue}-${request.pr}-${request.headSha}`)]
  const list=io.__freshListRefs??io.listRefs?.bind(io)
  if(typeof list!=='function')fail('complete native terminal-state inventory required')
  for(const terminalPrefix of terminalPrefixes){const rows=list(terminalPrefix);if(!Array.isArray(rows)||rows.length>=REVIEW_REF_ROW_LIMIT)fail('native terminal-state inventory incomplete');for(const row of rows){if(!row||!sha.test(row.sha??'')||!String(row.ref??'').startsWith(terminalPrefix))fail('native terminal-state inventory malformed');const suffix=String(row.ref).slice(terminalPrefix.length),slot=/^(?:-slot([1-9][0-9]*))?(?:-[1-9][0-9]*)?$/.exec(suffix);if(!slot)fail('native terminal-state identity malformed');if(Number(slot[1]??1)===request.slot)fail('existing native verdict/failure/replacement conflicts with missing-receipt disposition')}}
  const snapshot=typeof io.readReviewRecords==='function'?io.readReviewRecords(refs):null
  const readRef=ref=>snapshot?snapshot.get(ref)?.sha??null:io.readRef(ref)
  const readCommit=(ref,refSha)=>snapshot?.get(ref)?.commit??io.getCommit(refSha)
  const contractSha=readRef(d.contract_ref)
  if(!sha.test(contractSha??''))fail('original immutable contract is missing')
  const contractCommit=io.getCommit(contractSha),lines=messageOf(contractCommit).split(/\r?\n/)
  let contract;try{contract=parseStrictJson(lines.slice(2).join('\n').trim());validateContract(contract)}catch{fail('original immutable contract is malformed')}
  const owner=declaredDispositionOwner(contract.dispatcher,{env,machine})
  if(contract.worktree!==root||contract.work_issue!==request.issue||contract.branch!==pr.head.ref||d.contract_ref!==`refs/db-contracts/${contract.work_issue}/${contract.generation??1}`)fail('original contract/source pair differs')
  const contractPath=`.agent/work/${contract.work_issue}/${contract.generation??1}/contract.json`,completionPath=contractPath.replace('contract.json','completion.json')
  let checked,completion
  try{checked=parseStrictJson(git(root,['show',`${request.headSha}:${contractPath}`]));completion=parseStrictJson(git(root,['show',`${request.headSha}:${completionPath}`]));validateCompletionReport(completion,{validateCompletionRecord});validatePullRequestCompletion(completion,{pr:request.pr,headSha:request.headSha});if(completion.work_issue!==request.issue)throw Error('completion issue mismatch');if(!reconcileReportWithContract(completion,checked).satisfied)throw Error('contract not satisfied')}catch{fail('original native completion lineage is unavailable')}
  if(contractHash(checked)!==contractHash(contract))fail('original published contract differs from source')
  // Reuse native full Git evidence classification, including predecessor binding.
  const evidenceIo={isAncestor:(a,b)=>{try{git(root,['merge-base','--is-ancestor',a,b]);return true}catch{return false}},changedFiles:(a,b)=>git(root,['diff','--name-only','--diff-filter=ACDMRTUXB',a,b]).trim().split('\n').filter(Boolean),mergeBase:(a,b)=>git(root,['merge-base',a,b]).trim(),readPublishedContract:ref=>{const s=io.readRef(ref);if(!sha.test(s??''))fail('contract predecessor missing');return parseStrictJson(messageOf(io.getCommit(s)).split(/\r?\n/).slice(2).join('\n').trim())}}
  verifyGitEvidence({contract:checked,report:completion,prBaseSha:pr.base?.sha??pr.baseRefOid??completion.base_sha??contract.base_sha,prHeadSha:request.headSha},evidenceIo)
  const assignmentSha=readRef(assignmentRef)
  if(!sha.test(assignmentSha??''))fail('original assignment missing')
  const assignment=parseReviewCursor(readCommit(assignmentRef,assignmentSha))
  if(!sameTuple({...assignment,slot:assignment.slot??1},request))fail('original assignment tuple mismatch')
  const startSha=readRef(startRef)
  if(!sha.test(startSha??''))fail('original paid start missing')
  const start=paidStart({ref:startRef,sha:startSha},readCommit(startRef,startSha))
  if(!start||!sameTuple(start,request)||start.receiptPathSha256!==hash(d.receipt_path)||!digest.test(start.sourceDigest??''))fail('original paid start/source destination mismatch')
  const publishedAt=contractCommit.committedDate??contractCommit.committer?.date??contractCommit.commit?.committer?.date
  const implementedAt=git(root,['show','-s','--format=%cI',completion.head_sha]).trim()
  if(!Number.isFinite(Date.parse(publishedAt))||Date.parse(publishedAt)>=Date.parse(implementedAt)||Date.parse(publishedAt)>=Date.parse(start.startedAt))fail('original publication does not predate implementation and paid start')
  const lifecycle=privateJson(d.lifecycle_file),l=lifecycle.value
  const stateRoot=env.AI_REVIEW_LIFECYCLE_DIR??path.join(homedir(),'.local','state','ai-devops','review-lifecycle')
  if(typeof l.caller!=='string'||!l.caller||l.repository_key!==hash('https://github.com/popcre/shared-db')||!/^\d{8}T\d{6}-[0-9]+-[0-9]+$/.test(l.run_id??'')||d.lifecycle_file!==path.join(stateRoot,'runs',l.repository_key,'muse',l.caller,`${l.run_id}.json`))fail('lifecycle is outside its native original run namespace')
  if(l.schema_version!==1||l.status!=='completed'||l.provider!=='muse'||!/^[A-Za-z0-9._-]{1,128}$/.test(l.caller??'')||['.','..'].includes(l.caller)||l.implementer_engine!=='codex'||l.review_mode!=='final-check'||l.stale!==false||l.failure_class!==null||l.repository_root!==root||l.normalized_upstream!=='https://github.com/popcre/shared-db'||l.head!==request.headSha||l.source_digest!==start.sourceDigest||!['APPROVE','REVISE','REJECT'].includes(l.verdict)||!digest.test(l.packet_sha256??'')||!digest.test(l.report_sha256??'')||!Number.isFinite(Date.parse(l.started_at))||!Number.isFinite(Date.parse(l.finished_at))||Date.parse(l.started_at)<Date.parse(start.startedAt)||Date.parse(l.finished_at)<Date.parse(l.started_at))fail('native completed lifecycle does not bind the original paid source')
  const history=io.readPaidReviewStarts?.(`${REVIEW_STARTED_REF_PREFIX}/`,request.pr)
  if(!Array.isArray(history)||history.length>=REVIEW_REF_ROW_LIMIT)fail('complete original paid-start inventory is unavailable')
  const starts=[],seenStarts=new Set()
  for(const row of history){
    if(!row||typeof row.ref!=='string'||seenStarts.has(row.ref))fail('original paid-start inventory is malformed or duplicated')
    seenStarts.add(row.ref)
    let parsed;try{parsed=paidStart(row,row.commit??io.getCommit(row.sha))}catch{fail('original paid-start inventory contains malformed immutable evidence')}
    // Only established native unstarted-reclaim/independence tombstones return
    // null. Malformed starts throw above; they never disappear from uniqueness.
    if(parsed===null)continue
    if(parsed.issue===request.issue&&parsed.pr===request.pr&&parsed.headSha===request.headSha&&parsed.slot===request.slot&&!REVIEWERS.some(r=>r.name===parsed.reviewer))fail('original source paid start has an unknown provider')
    starts.push(parsed)
  }
  const exact=starts.filter(row=>sameTuple(row,request)&&row.ref===startRef&&row.sha===startSha)
  const competitors=starts.filter(row=>row.issue===request.issue&&row.pr===request.pr&&row.headSha===request.headSha&&row.slot===request.slot&&REVIEWERS.find(r=>r.name===row.reviewer)?.provider==='muse'&&row.ref!==startRef&&Date.parse(row.startedAt)>=Date.parse(start.startedAt)&&Date.parse(row.startedAt)<=Date.parse(l.finished_at))
  if(exact.length!==1||competitors.length)fail('native completion is ambiguous across original paid starts')
  const report=protectedDispositionBytes(l.report_path,4194304),body=report.bytes.toString('utf8')
  lifecyclePoolReportBody(`${JSON.stringify(l)}\n${l.report_path}`,{headSha:request.headSha,provider:'muse',worktree:root,sourceDigest:start.sourceDigest,readReport:()=>body})
  if(path.dirname(report.path)!==path.join(root,'.ai','reviews')||report.sha256!==l.report_sha256||!body.includes(`| reviewed commit | \`${request.headSha}\` |`)||!body.includes(`| source digest | \`${start.sourceDigest}\` |`)||!body.includes(`| packet | \`${l.packet_sha256}\` |`)||!body.includes(`| run | \`${l.run_id}\` |`)||!new RegExp(`(?:^|\\n)## Verdict\\n${l.verdict}\\s*$`).test(body))fail('original formal report/source/decision mismatch')
  if(path.dirname(l.packet_dir)!==path.join(root,'.ai','reviews','packets')||realpathSync(l.packet_dir)!==l.packet_dir)fail('original retained packet custody mismatch')
  const packetStat=lstatSync(l.packet_dir)
  if(!packetStat.isDirectory()||packetStat.uid!==process.getuid()||(packetStat.mode&0o077)!==0)fail('original retained packet directory is not private')
  const marker=protectedDispositionBytes(path.join(l.packet_dir,'.ai-review-packet'),16384).bytes.toString('utf8').split('\n')
  if(marker[3]!==l.packet_sha256)fail('retained marker does not preserve the consumed original packet seal')
  packetRead(['verify-retained',l.packet_dir])
  const identity=privateJson(path.join(l.packet_dir,'identity.json')).value
  if(identity.repository!==root||identity.head!==request.headSha||identity.source_digest!==start.sourceDigest)fail('retained packet original identity mismatch')
  const current=parseStrictJson(packetRead(['resolve','--repo',root,'--base',identity.base,'--assert-head',request.headSha]))
  if(current.source_digest!==start.sourceDigest||current.repository!==root)fail('original live source digest changed')
  const leaseSha=readRef(leaseRef),priorSha=readRef(dispositionRef),prior=priorSha?{...parseCompletedUnrecordable(readCommit(dispositionRef,priorSha),request),ref:dispositionRef,sha:priorSha}:null
  if(prior&&leaseSha!==null)fail('disposed lease has a new occupant')
  if(!prior&&(leaseSha!==assignmentSha||!sameTuple({...parseReviewLease(readCommit(leaseRef,leaseSha)),slot:request.slot},request)))fail('original exact lease is absent or changed')
  const bindings=[{ref:d.contract_ref,sha:contractSha},{ref:assignmentRef,sha:assignmentSha},{ref:startRef,sha:startSha},{ref:leaseRef,sha:assignmentSha}]
  const record={schema_version:1,kind:'completed-unrecordable-missing-source-receipt',...request,observed_verdict:l.verdict,authorizing:false,paid_attempt_consumed:true,...owner,bindings,proof_sha256:hash(JSON.stringify([descriptor.sha256,lifecycle.sha256,report.sha256,l.packet_sha256,contractHash(contract),start.sourceDigest]))}
  absentReceipt(d.receipt_path)
  if(prior){const {ref:oldRef,sha:oldSha,...previous}=prior;if(contractHash(previous)!==contractHash(record))fail('existing disposition differs from the exact original proof');return {request,prior}}
  return {request,record,ref:completedUnrecordableRef(request),leaseRef,leaseSha,bindings}
}

// Consume the owned lease and mutex in the SAME atomic push. Immutable source
// refs are provenance snapshots: unchanged Git refspecs are not CAS assertions.
// No sequential fallback: uncertainty is reconciled by readback, never another draw.
export function commitCompletedDisposition(proof,ownerSha,io,mutexRef) {
  if(typeof io.atomicReviewRefs!=='function'||typeof io.readReviewRefs!=='function')fail('atomic ref support required')
  if(proof.prior)return {authorizing:false,paid_attempt_consumed:true,alreadyDisposed:true,ref:proof.prior.ref,sha:proof.prior.sha,observed_verdict:proof.prior.observed_verdict}
  const {record,ref,leaseRef,leaseSha}=proof
  parseCompletedUnrecordable({message:`db-coordination completed-unrecordable\n${JSON.stringify(record)}`},proof.request)
  if(!sha.test(ownerSha??''))fail('owned mutex required')
  const recordSha=io.makeOwnerCommit(`db-coordination completed-unrecordable\n${JSON.stringify(record)}`)
  if(!sha.test(recordSha??''))fail('disposition commit is unreadable')
  const changes=[{ref:mutexRef,expected:ownerSha,sha:null},{ref,expected:null,sha:recordSha},{ref:leaseRef,expected:leaseSha,sha:null}]
  let uncertain=false
  try{io.atomicReviewRefs(changes)}catch{uncertain=true}
  const after=io.readReviewRefs(changes.map(c=>c.ref))
  if(!(after instanceof Map)||changes.some(c=>!after.has(c.ref))||!(after.get(mutexRef)===null||sha.test(after.get(mutexRef)??''))||after.get(ref)!==recordSha||after.get(leaseRef)!==null||after.get(mutexRef)===ownerSha)fail(uncertain?'atomic outcome unproved; preserve original records and reconcile, never blindly retry':'atomic disposition readback mismatch')
  return {authorizing:false,paid_attempt_consumed:true,alreadyDisposed:false,ref,sha:recordSha,observed_verdict:record.observed_verdict,mutex_released:true}
}

// An immutable negative decision remains negative across main/evidence refreshes.
// The existing paid-content proof, not a new generation/head, must witness real code correction.
export function assertNoDisposedNegativeReuse(request,io) {
  if(!sha.test(String(request.headSha??'')))return
  const start=`${prefix}/${Number(request.issue)}-${Number(request.pr)}-`
  const list=io.__freshListRefs??io.listRefs?.bind(io)
  if(!list){if(io.requiresExactReviewHeadSha)fail('complete disposition inventory capability required');return}
  const snapshot=io.__completedDispositionSnapshot?.(request.issue,request.pr)
  const rows=snapshot?snapshot.rows:list(start)
  if(!Array.isArray(rows)||rows.length>=128)fail('complete disposition inventory unavailable')
  const records=snapshot?.records??(rows.length&&typeof io.readReviewRecords==='function'?io.readReviewRecords(rows.map(r=>r.ref)):null)
  for(const row of rows){
    if(!sha.test(row.sha??''))fail('disposition inventory ref unreadable')
    const observed=records?.get(row.ref)
    if(records&&(!observed?.sha||observed.sha!==row.sha))fail('disposition inventory changed during qualification')
    const record=parseCompletedUnrecordable(observed?.commit??row.commit??io.getCommit(row.sha))
    if(row.ref!==completedUnrecordableRef(record)||record.issue!==Number(request.issue)||record.pr!==Number(request.pr))fail('disposition inventory identity mismatch')
    if(record.headSha===request.headSha)fail('disposed completed head cannot allocate a fresh namespace or continue')
    if(record.observed_verdict==='APPROVE')continue
    if(record.headSha===request.headSha)fail('negative completed decision requires genuine rejected-code correction')
    const comparison=io.reviewContentComparison?.(record.headSha,request.headSha,Number(request.pr),{})
    const proof=comparison?.budgetProof
    if(!proof||proof.kind!=='substantive'||proof.before!==record.headSha||proof.after!==request.headSha||!proof.witness||typeof proof.witness.path!=='string')fail('negative completed decision lacks genuine code-correction proof')
  }
}
