# Step 7 live proof: unattended reviewer start reroute (issue #3242)

Programme popcre/ai-devops#401, Step 7. Non-orchestrator work (no database structure change).

## What is being proved

1. The reviewer start watcher runs without a person invoking it. The replacement draw needs `ai-review-preflight` and the reviewer wrappers, which a GitHub-hosted runner does not have, so the unattended runner is the edge-dev scheduled task `\ai-devops\reviewer-start-watch` (popcre/ai-devops#599, `bin/ai-reviewer-start-watch tick` every 2 minutes). It runs `scripts/orchestrator-flow/reviewer-start-watch.mjs --apply` from a fresh clone of `main` and logs each pass to `~/.ai-devops/reviewer-start-watch/tick.log`.
2. One live unstarted reviewer is rerouted by an unattended pass at the first pass after its 10-minute start SLO, while the other slot's verdict stays intact.

Assumption: "within 10 minutes of its draw" is read as "at the first watcher pass after the 10-minute start SLO". A lease cannot be declared a non-start before the SLO ends, so the bound is the SLO plus one pass interval.

## Set-up (staged)

This pull request is itself the subject. Slot 1 is drawn and reviewed normally. Slot 2 is drawn and deliberately never started, so it is a real governed lease that stays unstarted. No watcher pass is invoked by hand.

## Evidence

Recorded below once the unattended pass has acted.
