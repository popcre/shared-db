# Step 7 live proof: unattended reviewer start reroute (issue #3242)

Programme popcre/ai-devops#401, Step 7. Non-orchestrator work (no database structure change).

## What is being proved

1. The reviewer start watcher runs without a person invoking it: `.github/workflows/reviewer-start-watch.yml` on `main` (#3243, relay form #3257).
2. One live unstarted reviewer is rerouted by an unattended pass at the first pass after its 10-minute start SLO, while the other slot's lease stays intact.

## Set-up

This pull request is itself the subject. Slot 1 is drawn and reviewed normally; slot 2 is drawn and deliberately never started, so it is a real governed lease that stays unstarted. No watcher pass is invoked by hand.

## Evidence

Recorded below once the unattended pass has acted.
