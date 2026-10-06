import { mkdtempSync, writeFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { createHash } from 'node:crypto'
// Owner: reviewer assignment lane. Immutable start records bound paid rounds.
import { readStoredHashRegistry, normalizedStoredHashFile } from '../pr-content-equivalence.mjs'
import { LaneError } from './claims.mjs'
import { REVIEW_STARTED_REF_PREFIX, REVIEW_REF_ROW_LIMIT } from './constants.mjs'
import { parseTerminalFailureEvidence } from './review-replacement.mjs'

export function paidStart(row, commit) {
  const tuple = /^refs\/db-review-started\/(\d+)-(\d+)-([0-9a-f]{40})-slot(\d+)-seq(\d+)$/.exec(row.ref)
  if (!tuple || !/^[0-9a-f]{40}$/.test(row.sha)) throw new LaneError('review circuit breaker: malformed immutable start ref')
  const [, issue, pr, headSha, slot, sequence] = tuple
  const message = String(commit?.message ?? commit?.commit?.message ?? '')
  const start = /^db-coordination review-started issue=(\d+) pr=(\d+) head=([0-9a-f]{40}) slot=(\d+) sequence=(\d+) reviewer=([a-z0-9.-]+) at=(\S+)(?: session=([A-Za-z0-9._-]+) receipt-path=sha256:[0-9a-f]{64} source=sha256:[0-9a-f]{64})?$/.exec(message)
  if (start) {
    if (start.slice(1,6).join(':') !== tuple.slice(1).join(':') || !Number.isFinite(Date.parse(start[7]))) throw new LaneError('review circuit breaker: start record binding mismatch')
    return {issue:Number(issue),pr:Number(pr),headSha,slot:Number(slot),sequence:Number(sequence),reviewer:start[6]}
  }
  // Only the established atomic unstarted reclaim / independence conflict can
  // occupy a start marker without spending a provider attempt.
  const silence = /^db-coordination reviewer-silence-release reviewer=([a-z0-9.-]+) issue=(\d+) pr=(\d+) head=([0-9a-f]{40}) sequence=(\d+) code=silent_worker_observed probe=([0-9a-f]{40}) observed-at=(\S+) confirmed-at=(\S+) verdict=none artifact=none replacement=none$/.exec(message)
  if (silence && [silence[2],silence[3],silence[4],silence[5]].join(':') === [issue,pr,headSha,sequence].join(':') && Number.isFinite(Date.parse(silence[7])) && Number.isFinite(Date.parse(silence[8]))) return null
  const conflict=/^db-coordination reviewer-failure-replacement sequence=(\d+) reviewer=([a-z0-9.-]+) issue=(\d+) pr=(\d+) head=([0-9a-f]{40}) slot=(\d+)(?: allowlist=[a-z0-9.,-]+)? failed-sequence=(\d+) prior-sequence=(\d+) failure-ref=self failed-reviewer=([a-z0-9.-]+) code=slot_independence_conflict(?: failing-check=[a-z0-9_.-]+)? verdict=none artifact=none$/.exec(message)
  if(conflict && [conflict[3],conflict[4],conflict[5],conflict[6],conflict[7]].join(':') === tuple.slice(1).join(':')) return null
  throw new LaneError('review circuit breaker: unrecognized or unreadable start evidence')
}

// Budget provenance is separate from strict review-diff equivalence. Git may
// write unreferenced merge-tree cache objects, never refs or source files.
export function derivePaidContentProof(before, after, protectedMain, git, excludePaths = []) {
  const sha = /^[0-9a-f]{40}$/
  if (![before,after,protectedMain].every(x=>sha.test(x))) throw new LaneError('review budget Git scope unreadable')
  const run = args => String(git(args)).trim()
  const ancestor = (a,b) => { try { run(['merge-base','--is-ancestor',a,b]); return true } catch (error) { if(error?.status===1)return false;throw error } }
  const registry=readStoredHashRegistry(protectedMain,{gitRunner:git})
  const stored=[...new Set(registry.map(entry=>entry.file))]
  const canonicalAppends=[]
  const paths = [':(top)**', ...[...excludePaths,...stored].map(p=>`:(top,literal,exclude)${p}`)]
  const tree = value => typeof value==='string'?value:value.tree
  const raw = args => String(git(args))
  const entry = (commit,file) => {
    const record=raw(['ls-tree','-z',tree(commit),'--',file]).split('\0').filter(Boolean)
    if(record.length!==1)throw new LaneError('review budget canonical blob missing')
    const match=/^(100644|100755) blob ([0-9a-f]{40})\t(.+)$/.exec(record[0])
    if(!match || match[3]!==file)throw new LaneError('review budget canonical regular mode unreadable')
    const text=raw(['show',`${tree(commit)}:${file}`])
    if(Buffer.byteLength(text)>1048576 || createHash('sha1').update(`blob ${Buffer.byteLength(text)}\0`).update(text).digest('hex')!==match[2])throw new LaneError('review budget canonical blob bytes unreadable or oversized')
    return {mode:match[1],blob:match[2],text}
  }
  const equal = (a,b) => {
    const overrides=a?.overrides??new Map()
    const selected=[...overrides.keys()]
    if(run(['diff','--name-only',tree(a),tree(b),'--',...paths,...selected.map(p=>`:(top,literal,exclude)${p}`)])!=='')return false
    if(!stored.every(file=>normalizedStoredHashFile(tree(a),file,registry,{gitRunner:git})===normalizedStoredHashFile(tree(b),file,registry,{gitRunner:git})))return false
    return selected.every(file=>{const actual=entry(b,file),expected=overrides.get(file);return actual.mode===expected.mode && actual.text===expected.text})
  }
  const canonicalAppend = (a,b,base) => {
    const file='scripts/manage-migration-author-lanes.test.mjs'
    const blobs=[a,base,b].map(commit=>entry(commit,file))
    if(new Set(blobs.map(x=>x.mode)).size!==1 || blobs.some(x=>/^(?:<{7}|\|{7}|={7}|>{7})/m.test(x.text)))throw new LaneError('review budget canonical append mode or marker ambiguity refused')
    const dir=mkdtempSync(path.join(tmpdir(),'review-budget-append-'))
    const labels=[`budget-ours-${a}`,`budget-base-${base}`,`budget-main-${b}`]
    try {
      const files=blobs.map((blob,i)=>{const f=path.join(dir,String(i));writeFileSync(f,blob.text);return f})
      let merged
      try { merged=raw(['merge-file','--diff3','-p','-L',labels[0],'-L',labels[1],'-L',labels[2],...files]);throw new LaneError('review budget canonical append requires exactly one conflict') }
      catch(error) { if(error?.status!==1 || typeof error.stdout!=='string')throw error;merged=error.stdout }
      if(Buffer.byteLength(merged)>3145728)throw new LaneError('review budget append output oversized')
      const markers=[`<<<<<<< ${labels[0]}\n`,`||||||| ${labels[1]}\n`,'=======\n',`>>>>>>> ${labels[2]}\n`]
      const positions=markers.map(marker=>{const index=merged.indexOf(marker);if(index<0 || merged.indexOf(marker,index+marker.length)!==-1)throw new LaneError('review budget append marker ambiguity');return index})
      if(!positions.every((index,i)=>i===0 || index>positions[i-1]) || positions[3]+markers[3].length!==merged.length)throw new LaneError('review budget append must be one EOF conflict')
      const ours=merged.slice(positions[0]+markers[0].length,positions[1])
      const ancestorBytes=merged.slice(positions[1]+markers[1].length,positions[2])
      const theirs=merged.slice(positions[2]+markers[2].length,positions[3])
      if(ancestorBytes!=='' || ours.trim()==='' || theirs.trim()==='')throw new LaneError('review budget append cannot modify old lines or omit a parent')
      const text=merged.slice(0,positions[0])+ours+theirs
      canonicalAppends.push({base,parents:[a,b],path:file,mode:blobs[0].mode,parentBlobs:blobs.map(x=>x.blob),canonicalBlob:createHash('sha1').update(`blob ${Buffer.byteLength(text)}\0`).update(text).digest('hex')})
      return new Map([[file,{mode:blobs[0].mode,text}]])
    } finally { rmSync(dir,{recursive:true,force:true}) }
  }
  const merge = (a,b) => {
    if (ancestor(b,a)) return run(['rev-parse',`${a}^{tree}`])
    const base=run(['merge-base',a,b])
    if(!sha.test(base))throw new LaneError('review budget merge base unreadable')
    const changed=[...new Set([a,b].flatMap(tip=>raw(['diff','--name-only','-z',base,tip]).split('\0').filter(Boolean)))]
    if(changed.length>=1000)throw new LaneError('review budget merge path bound refused')
    for(const tip of [base,a,b,null]) {
      const attributes=changed.length?raw(['check-attr',...(tip?[`--source=${tip}`]:[]),'-z','merge','filter','working-tree-encoding','--',...changed]).split('\0'):[]
      for(let i=2;i<attributes.length;i+=3)if(attributes[i]!=='unspecified')throw new LaneError('review budget custom merge/filter/encoding attributes refused')
      if(tip && raw(['diff','--name-status','-M',base,tip]).split('\n').some(line=>/^R[0-9]+\t/.test(line)))throw new LaneError('review budget renamed merge source refused')
    }
    let result
    try { result=run(['merge-tree','--write-tree',a,b]) }
    catch(error) {
      if(error?.status!==1 || typeof error.stdout!=='string')throw error
      const lines=error.stdout.split('\n'),resultTree=lines[0]
      const stages=lines.slice(1).filter(line=>/^[0-9]{6} /.test(line))
      if(!sha.test(resultTree) || stages.length!==3 || !stages.every((line,i)=>new RegExp(`^(100644|100755) [0-9a-f]{40} ${i+1}\\tscripts/manage-migration-author-lanes\\.test\\.mjs$`).test(line)))throw new LaneError('review budget conflict is outside the one canonical test append')
      return {tree:resultTree,overrides:canonicalAppend(a,b,base)}
    }
    if (!sha.test(result)) throw new LaneError('review budget automatic merge proof unreadable')
    return result
  }
  try {
    const incorporatedMain = run(['merge-base',after,protectedMain])
    if (!sha.test(incorporatedMain)) throw new LaneError('review budget protected main ancestry unreadable')
    const expected = merge(before,incorporatedMain)
    if (equal(expected,after)) return {schema:1,before,after,protectedMain,kind:'unchanged',canonicalAppends}
    const rows = run(['rev-list','--first-parent','--max-count=1001',after]).split('\n')
    const index = rows.indexOf(before)
    if (index < 0 || index >= 1000) throw new LaneError('review budget complete first-parent ancestry unavailable')
    const authorCandidates=[]
    let authored = false,witness=null
    for (const commit of rows.slice(0,index)) {
      const parents = run(['rev-list','--parents','-n','1',commit]).split(' ').slice(1)
      if (parents.length === 2) {
        if (!ancestor(parents[1],protectedMain) || !equal(merge(...parents),commit)) throw new LaneError('review budget noncanonical or foreign merge refused')
      } else if (parents.length === 1) {
        if (!ancestor(commit,protectedMain)) {
          authorCandidates.push({commit,parent:parents[0]})
        }
      } else throw new LaneError('review budget ambiguous merge provenance refused')
    }
    const witnessExcludes=canonicalAppends.length?[':(top,literal,exclude)scripts/manage-migration-author-lanes.test.mjs']:[]
    const netPaths=run(['diff','--name-only',tree(expected),after,'--',...paths,...witnessExcludes]).split('\n').filter(Boolean)
    for(const {commit,parent} of authorCandidates) {
      const changed=run(['diff','--name-only',parent,commit,'--',...paths]).split('\n')
      for(const file of netPaths.filter(file=>changed.includes(file))) {const original=entry(commit,file),actual=entry(after,file);if(original.mode===actual.mode && original.blob===actual.blob){authored=true;witness={commit,path:file,mode:original.mode,blob:original.blob}}}
    }
    if (!authored) throw new LaneError('review budget surviving author source edit unavailable')
    return {schema:1,before,after,protectedMain,kind:'substantive',historyCount:index,witness,canonicalAppends}
  } catch (error) {
    throw new LaneError(`review budget Git provenance refused: ${String(error?.message??error).split('\n')[0]}`)
  }
}

export function assertPaidReviewCapacity(request, io) {
  if(!Number.isInteger(request.pr)||request.pr<1||!Number.isInteger(request.slot)||request.slot<1)throw new LaneError('review circuit breaker: exact positive PR and slot required')
  const prefix=`${REVIEW_STARTED_REF_PREFIX}/`
  const rows = typeof io.readPaidReviewStarts === 'function' ? io.readPaidReviewStarts(prefix,request.pr) : io.listRefs(prefix)
  if (!Array.isArray(rows)) throw new LaneError('review circuit breaker: immutable start listing unreadable')
  if(rows.length>=REVIEW_REF_ROW_LIMIT)throw new LaneError('review circuit breaker: bounded start listing may be truncated')
  const starts = rows.map(row=>paidStart(row,row.commit ?? io.getCommit(row.sha))).filter(row=>row && row.pr === request.pr && row.slot === request.slot)
  let count=0
  const comparisonContext={}
  for (const start of starts) {
    let same=start.headSha === request.headSha
    if (!same) {
      if (typeof io.reviewContentComparison !== 'function') throw new LaneError('review circuit breaker: substantive content comparison unavailable')
      const comparison=io.reviewContentComparison(start.headSha,request.headSha,request.pr,comparisonContext)
      if (!comparison || !/^[0-9a-f]{64}$/.test(comparison.before) || !/^[0-9a-f]{64}$/.test(comparison.after)) throw new LaneError('review circuit breaker: substantive content proof unreadable')
      const proof=comparison.budgetProof
      if(!proof || proof.schema!==1 || proof.before!==start.headSha || proof.after!==request.headSha || !/^[0-9a-f]{40}$/.test(proof.protectedMain??'') || !['unchanged','substantive'].includes(proof.kind)) throw new LaneError('review circuit breaker: author-owned Git provenance proof unreadable')
      if(proof.kind==='substantive' && (!Number.isInteger(proof.historyCount)||proof.historyCount<1||proof.historyCount>=1000)) throw new LaneError('review circuit breaker: complete substantive history proof unreadable')
      same=proof.kind==='unchanged'
    }
    if(same) count++
  }
  if(count>=2) throw new LaneError(`review circuit breaker: two paid attempts already started for unchanged reviewed content in slot ${request.slot}; third draw refused pending substantive repair or supported cause-bound reinstatement proof`)
  return {paidAttempts:count,remaining:2-count}
}

// Provider outage/quota evidence differs from a local preparation failure.
export function pauseActualReviewFailure(record,io) {
  if(!['insufficient_quota','provider_unavailable'].includes(record.failureCode))return {paused:false,reason:'not a verified provider failure class'}
  if(typeof io.readPaidReviewStarts!=='function'||typeof io.pauseReviewerFailure!=='function')throw new LaneError('verified provider failure requires the supported monotonic pause bridge')
  const rows=io.readPaidReviewStarts(`${REVIEW_STARTED_REF_PREFIX}/`,record.pr)
  if(!Array.isArray(rows))throw new LaneError('provider failure paid-start lineage unreadable')
  const start=rows.map(row=>paidStart(row,row.commit??io.getCommit(row.sha))).find(row=>row&&row.issue===record.issue&&row.pr===record.pr&&row.headSha===record.headSha&&row.slot===record.slot&&row.sequence===record.failedSequence&&(!record.reviewer||row.reviewer===record.reviewer))
  if(!start)return {paused:false,reason:'no immutable paid-start evidence'}
  const boundRecord={...record,reviewer:start.reviewer}
  const commit=typeof io.readReviewFailureCommit==='function'?io.readReviewFailureCommit(record.failureSha):io.getCommit(record.failureSha)
  const failure=parseTerminalFailureEvidence(commit)
  if(!failure || ['issue','pr','headSha','failedSequence','reviewer','failureCode'].some(key=>failure[key]!==boundRecord[key]))throw new LaneError('provider pause immutable terminal failure binding mismatch')
  const timestamp=commit?.committedDate??commit?.commit?.committer?.date
  const observed=Date.parse(timestamp)
  if(typeof timestamp!=='string'||!Number.isFinite(observed)||observed<0)throw new LaneError('provider pause immutable failure timestamp unreadable')
  const result=io.pauseReviewerFailure({...boundRecord,observedEpoch:Math.floor(observed/1000)})
  return result?.status==='expired'?{paused:false,reason:'original failure window expired',...result}:{paused:true}
}
