const APPLY_PATH='.github/workflows/shared-supabase-migrations.yml'
const RECOVERY_PATH='.github/workflows/production-catalog-verification-recovery.yml'
const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b)
export function matchesCatalogRecovery({evidence,applyRun,recoveryRun,recoveryArtifact,binding,catalog,versions,manifest,jobs,ledgerBefore,ledgerAfter,ledgerLive}) {
  if(applyRun?.status!=='completed'||applyRun.conclusion!=='failure'||applyRun.event!=='workflow_dispatch'||applyRun.path!==APPLY_PATH||applyRun.head_sha!==evidence.production_commit_sha)return false
  if(recoveryRun?.status!=='completed'||recoveryRun.conclusion!=='success'||recoveryRun.event!=='workflow_dispatch'||recoveryRun.path!==RECOVERY_PATH||recoveryRun.head_sha!==evidence.production_recovery_commit_sha)return false
  if(recoveryArtifact?.expired!==false||recoveryArtifact.name!==`production-catalog-recovery-${applyRun.id}`||Number(recoveryArtifact.id)!==evidence.production_recovery_artifact_id||recoveryArtifact.digest!==evidence.production_recovery_artifact_digest)return false
  const failed=(jobs?.jobs??[]).filter(j=>j.conclusion==='failure')
  if(failed.length!==1||failed[0].name!=='Production apply (automatic evidence gates)'||(jobs?.jobs??[]).some(j=>!['success','skipped','failure'].includes(j.conclusion)))return false
  const steps=failed[0].steps??[]
  for(const name of ['SQL migration guards','Production apply review (immutable evidence + hard guards)'])if((jobs.jobs??[]).filter(j=>j.name===name&&j.conclusion==='success').length!==1)return false
  if(!same(steps.filter(s=>s.conclusion==='failure').map(s=>s.name),['Post-apply catalog verification']))return false
  for(const name of ['Build bounded checkout','Fresh dry-run, then apply','Capture production migration record (after)','Save apply evidence','Release the exclusive production lane with ownership proof'])if(steps.filter(s=>s.name===name&&s.conclusion==='success').length!==1)return false
  const wanted=[...versions].sort()
  if(!wanted.length||new Set(wanted).size!==wanted.length)return false
  const ledger=text=>new Set(String(text??'').split(/\r?\n/).map(line=>/^\s*(?:\d{14})?\s*\|\s*(\d{14})\s*\|/.exec(line)?.[1]).filter(Boolean))
  const before=ledger(ledgerBefore),after=ledger(ledgerAfter),live=ledger(ledgerLive)
  if(!same([...after].filter(v=>!before.has(v)).sort(),wanted)||[...before].some(v=>!after.has(v))||[...after].some(v=>!live.has(v)))return false
  if(binding?.schema_version!==1||binding.project_ref!=='qsllyeztdwjgirsysgai'||binding.main_sha!==evidence.production_recovery_commit_sha||binding.apply_main_sha!==evidence.production_commit_sha||binding.apply_run_id!==applyRun.id||binding.apply_artifact_id!==evidence.production_artifact_id||binding.apply_artifact_digest!==evidence.production_artifact_digest||!same(binding.allowlist,wanted)||!same(binding.ledger_added,wanted)||!same(binding.ledger_removed,[])||binding.catalog_enforced!==true||binding.verification_only!==true||binding.original_failure!=='Post-apply catalog verification')return false
  if(!same(Object.keys(binding.migration_hashes??{}).sort(),wanted)||wanted.some(v=>!/^[a-f0-9]{64}$/.test(binding.migration_hashes[v])||manifest?.[v]!==binding.migration_hashes[v]))return false
  if(catalog?.enforcing!==true||!same(catalog.errors,[])||!same(catalog.allowlist,wanted))return false
  for(const version of wanted){
    const checks=(catalog.behavior_checks??[]).filter(c=>c.kind==='catalog_contract'&&c.migration_version===version&&c.migration_sha256===binding.migration_hashes[version])
    if(!checks.length)return false
    for(const check of checks){const results=(catalog.behavior_results?.behavior_checks??[]).filter(r=>r.id===check.id);if(!Number.isSafeInteger(check.expected_count)||check.expected_count<1||results.length!==1||results[0].actual_count!==check.expected_count||results[0].expected_count!==check.expected_count)return false}
  }
  return true
}
