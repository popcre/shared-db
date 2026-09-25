// Trusted pure-prose fast CI route (issue #3383): workflow integration.
//
// The classifier is only safe if the workflow that runs it is base-trusted and
// fails closed. These tests assert that shape. They fail if the route workflow
// ever checks out or executes the pull request head, if it publishes a status
// that could be mistaken for a merge authorization (issue #3505), or if any
// required engineering suite can be skipped without a proven pure-prose
// inventory.
import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const read = (name) => readFileSync(fileURLToPath(new URL(`../.github/workflows/${name}`, import.meta.url)), 'utf8').replace(/\r\n/g, '\n')

const route = read('documents-fast-ci.yml')
const tools = read('tools-offline-tests.yml')
const promotion = read('coldlion-promotion-contract-tests.yml')

// ---------------------------------------------------------------------------
// The route workflow itself
// ---------------------------------------------------------------------------

test('the route workflow runs trusted base code and never the pull request head', () => {
  assert.match(route, /pull_request_target:/)
  assert.match(route, /merge_group:/)
  assert.match(route, /types: \[checks_requested\]/)
  // Base identity is proven BEFORE checkout.
  const proveBase = route.indexOf('name: Prove the protected base identity before checkout')
  const checkout = route.indexOf('name: Check out trusted base code only')
  assert.ok(proveBase >= 0 && proveBase < checkout, 'base identity must be proven before checkout')
  // Checkout is pinned to the protected base, never the head.
  assert.match(route, /ref: \$\{\{ github\.event\.pull_request\.base\.sha \|\| github\.event\.merge_group\.base\.sha \|\| github\.sha \}\}/)
  assert.doesNotMatch(route, /ref: \$\{\{ github\.event\.pull_request\.head/)
  // The head appears only as a fetch target and a diff argument.
  assert.doesNotMatch(route, /checkout@[\s\S]{0,200}head\.sha/)
})

test('the route workflow never executes anything from the head tree', () => {
  // There is exactly one checkout and it is the base.
  const checkouts = route.match(/uses: actions\/checkout@/g) ?? []
  assert.equal(checkouts.length, 1, 'the route workflow must have exactly one checkout, and it must be the base')
  // The head is fetched as an object, not checked out.
  assert.match(route, /git fetch .*"\$HEAD_SHA"/)
})

test('the route workflow is read-only and cannot weaken branch protection', () => {
  assert.match(route, /permissions:\n  contents: read/)
  assert.doesNotMatch(route, /statuses:\s*write/)
  assert.doesNotMatch(route, /contents:\s*write/)
  assert.doesNotMatch(route, /--admin/)
  assert.doesNotMatch(route, /--authorize-/)
  // It publishes NO commit status at all, so it can neither grant a merge
  // authorization nor collide with the #3505 shared context name.
  assert.doesNotMatch(route, /Documents-only merge authorization/)
  assert.doesNotMatch(route, /Migration guarded merge authorization/)
})

test('the route workflow fails closed when the inventory cannot be proven', () => {
  assert.match(route, /Fail closed: no comparable base\/head pair/)
  // The classification step only writes `route=pure-prose` from the classifier's
  // own success exit; every other path writes `route=full`.
  assert.match(route, /node scripts\/check-documents-ci-route\.mjs "\$BASE_SHA" "\$HEAD_SHA"/)
  const step = route.slice(route.indexOf('id: route'), route.indexOf('name: Publish the routing decision'))
  assert.match(step, /route=full/)
  assert.match(step, /route=pure-prose/)
  // The classifier and its tests are proven before they are trusted.
  assert.match(route, /name: Prove the classifier and its tests before trusting them/)
  assert.match(route, /check-documents-ci-route\.test\.mjs/)
})

test('the route workflow never cancels a merge_group run', () => {
  assert.match(route, /cancel-in-progress: \$\{\{ github\.event_name != 'merge_group' \}\}/)
})

test('the route workflow does not path-filter: a filtered route silently misses the change', () => {
  const onBlock = /^on:\n([\s\S]*?)^\w/m.exec(route)?.[1] ?? ''
  assert.ok(!/^ {4}paths(-ignore)?:/m.test(onBlock), 'the route workflow must not carry a paths filter')
})

// ---------------------------------------------------------------------------
// Engineering-suite skip wiring
// ---------------------------------------------------------------------------

for (const [name, text] of [['tools-offline-tests.yml', tools], ['coldlion-promotion-contract-tests.yml', promotion]]) {
  test(`${name} skips its engineering suite only on a proven pure-prose route`, () => {
    // The skip decision is produced by the trusted classifier, not by a paths
    // filter or a head-authored expression.
    assert.match(text, /check-documents-ci-route\.mjs/, `${name} must consult the route classifier`)
    // Fail closed: an absent classifier or an unreadable inventory takes the
    // full path. The wiring must be able to write a non-pure-prose decision.
    assert.match(text, /pure_prose=false/, `${name} must be able to refuse the fast route`)
    assert.match(text, /pure_prose=true/, `${name} must record a proven fast route`)
    // The classifier is extracted from the protected base tree so a head cannot
    // rewrite its own grader.
    assert.match(text, /git archive "\$BASE_SHA" scripts\/check-documents-ci-route\.mjs/, `${name} must extract the classifier from the protected base`)
    assert.match(text, /scratch=/, `${name} must run the classifier outside the working tree`)
    // Required context name is unchanged: the skip must not rename the job.
    assert.ok(text.includes('name: ${'), `${name} must keep its stable required-context job name`)
  })

  test(`${name} does not gain a paths filter or a weakened required context`, () => {
    const onBlock = /^on:\n([\s\S]*?)^\w/m.exec(text)?.[1] ?? ''
    assert.ok(!/^ {4}paths(-ignore)?:/m.test(onBlock), `${name} must not gain a paths filter`)
    assert.doesNotMatch(text, /continue-on-error:\s*true/, `${name} must not soften a failure into a warning`)
  })
}

// ---------------------------------------------------------------------------
// The existing documents-only lane must not be weakened
// ---------------------------------------------------------------------------

test('the documents-only merge authorization lane is untouched and still exclusive', () => {
  const documents = read('documents-only-merge-authorization.yml')
  assert.match(documents, /pull_request_target:/)
  assert.match(documents, /ref: \$\{\{ github\.event\.pull_request\.base\.sha \}\}/)
  assert.doesNotMatch(documents, /ref: \$\{\{ github\.event\.pull_request\.head/)
  assert.match(documents, /--authorize-repository-maintenance-status/)
  // The strict documents-only rules are still what the lane proves.
  const classifier = readFileSync(fileURLToPath(new URL('../scripts/lib/documents-only-change.mjs', import.meta.url)), 'utf8')
  assert.match(classifier, /RULEBOOK_BASENAMES = new Set\(\['agents\.md', 'claude\.md'\]\)/)
  assert.match(classifier, /DOCUMENT_EXTENSIONS = new Set\(\['\.md', '\.markdown', '\.txt', '\.rst'\]\)/)
  // The pure-prose route is STRICTER than the documents-only lane: it uses the
  // same non-rulebook prose definition plus a mode check, so it can never grant
  // something the documents-only lane refuses.
  assert.match(classifier, /PROSE_FILE_MODE = '100644'/)
  assert.match(classifier, /export function classifyProseGitInventory/)
})
