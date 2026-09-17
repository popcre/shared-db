import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  HISTORICAL_REPOSITORY_SLUG, RepositoryIdentityError, currentRepository, isThisRepositoryOrHistorical,
  parseGitHubRemoteUrl, parseRepositorySlug, readOriginUrl, resolveRepositoryIdentity,
} from './repository-identity.mjs'

const origin = (url) => () => url
const resolve = (opts) => resolveRepositoryIdentity({ env: {}, readOrigin: origin(null), ...opts })

test('explicit value is used and must agree with other sources', () => {
  assert.equal(resolve({ explicit: 'popcre/shared-db' }), 'popcre/shared-db')
  assert.throws(() => resolve({ explicit: 'popcre/shared-db', env: { GITHUB_REPOSITORY: 'u2giants/shared-db' } }), RepositoryIdentityError)
  assert.throws(() => resolve({ explicit: 'popcre/shared-db', readOrigin: origin('https://github.com/u2giants/shared-db.git') }), /disagreement/)
})

test('GitHub Actions GITHUB_REPOSITORY is used', () => {
  assert.equal(resolve({ env: { GITHUB_REPOSITORY: 'popcre/shared-db' } }), 'popcre/shared-db')
})

test('HTTPS and both SSH remote forms resolve, old and destination slugs alike', () => {
  for (const url of ['https://github.com/popcre/shared-db.git', 'https://x-access-token:abc@github.com/popcre/shared-db',
    'git@github.com:popcre/shared-db.git', 'ssh://git@github.com/popcre/shared-db.git']) {
    assert.equal(resolve({ readOrigin: origin(url) }), 'popcre/shared-db', url)
  }
  assert.equal(resolve({ readOrigin: origin('https://github.com/u2giants/shared-db') }), 'u2giants/shared-db')
})

test('malformed, non-GitHub and absent sources fail closed', () => {
  for (const url of ['https://gitlab.com/popcre/shared-db.git', 'https://github.com/popcre', 'C:/repos/shared-db', 'https://github.com.evil/popcre/shared-db']) {
    assert.throws(() => parseGitHubRemoteUrl(url), RepositoryIdentityError, url)
  }
  for (const bad of ['popcre', 'a/b/c', '../x', 'popcre/shared-db.git', 'popcre/ space', '']) {
    assert.throws(() => parseRepositorySlug(bad), RepositoryIdentityError, bad)
  }
  assert.throws(() => resolve({}), /cannot determine/)
  assert.throws(() => resolve({ env: { GITHUB_REPOSITORY: 'nonsense' } }), RepositoryIdentityError)
})

test('env and origin disagreement is refused; case-only difference agrees', () => {
  assert.throws(() => resolve({ env: { GITHUB_REPOSITORY: 'popcre/shared-db' }, readOrigin: origin('git@github.com:u2giants/shared-db.git') }), /refusing to guess/)
  assert.equal(resolve({ env: { GITHUB_REPOSITORY: 'PopCre/shared-db' }, readOrigin: origin('git@github.com:popcre/shared-db.git') }), 'PopCre/shared-db')
})

test('an unreadable origin is absent, not a guess', () => {
  assert.equal(readOriginUrl({ spawn: () => ({ status: 2, stdout: '' }) }), null)
  assert.equal(readOriginUrl({ spawn: () => ({ error: new Error('no git') }) }), null)
})

test('historical slug is accepted only for evidence, alongside the current one', () => {
  assert.equal(HISTORICAL_REPOSITORY_SLUG, 'u2giants/shared-db')
  assert.equal(isThisRepositoryOrHistorical('u2giants/shared-db', 'popcre/shared-db'), true)
  assert.equal(isThisRepositoryOrHistorical('popcre/shared-db', 'popcre/shared-db'), true)
  assert.equal(isThisRepositoryOrHistorical('someone/shared-db', 'popcre/shared-db'), false)
})

test('this checkout resolves to a slug', () => {
  assert.match(currentRepository(), /^[^/]+\/[^/]+$/)
})
