// Issue #2831 -- the single list of which reviewer wrappers can emit a GOVERNED verdict.
//
// A governed review is recorded only from one terminal line of the form
// `VERDICT: APPROVE|REVISE|REJECT <40-hex head sha>`. A wrapper that cannot be run in a
// way that ends with that line can be drawn, leased and never satisfied. The allocator
// (`scripts/manage-migration-author-lanes.mjs`) and the runner
// (`scripts/run-governed-review.mjs`) both read this module, so the capability fact and
// the runner's behaviour cannot drift apart.

// Every wrapper the governed runner will launch. A roster row whose wrapper is not here
// cannot produce a recordable governed verdict and is never drawn.
export const GOVERNED_VERDICT_WRAPPERS = Object.freeze(['ai-claude-review','ai-codex-review','ai-deepseek-agent','ai-gemini','ai-glm','ai-grok-review','ai-kimi','ai-muse','ai-qwen'])

// Wrappers that take the explicit `--governed-verdict <head>` contract flag.
export const VERDICT_CONTRACT_FLAG_WRAPPERS = Object.freeze(['ai-gemini','ai-qwen','ai-deepseek-agent'])

// Subcommands that force a verdict grammar a governed review cannot record. `ai-muse
// review` injects `VERDICT: FINDINGS|NO FINDINGS` (REQUIRE_VERDICT=1), which carries no
// decision and no head. Its `new`/`ask` subcommands take the governed prompt as written.
export const FORBIDDEN_GOVERNED_SUBCOMMANDS = Object.freeze({'ai-muse':Object.freeze(['review'])})

export function wrapperBaseName(wrapper){
  return String(wrapper??'').split(/[\\/]/).pop().replace(/\.(cmd|bat|exe)$/i,'').toLowerCase()
}

export function wrapperEmitsGovernedVerdict(wrapper){
  return GOVERNED_VERDICT_WRAPPERS.includes(wrapperBaseName(wrapper))
}

// The first positional argument is the subcommand. Returns the forbidden subcommand, or null.
export function forbiddenGovernedSubcommand(wrapper,args){
  const forbidden=FORBIDDEN_GOVERNED_SUBCOMMANDS[wrapperBaseName(wrapper)]
  if(!forbidden)return null
  const list=[...(args??[])].map(String)
  const start=list[0]==='--'?1:0
  const sub=list.slice(start).find((token)=>!token.startsWith('-'))
  return sub&&forbidden.includes(sub.toLowerCase())?sub:null
}
