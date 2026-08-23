// Store.js test suite. Run with: node --test tests/
'use strict'
process.env.TZ = 'UTC'

const test = require('node:test')
const assert = require('node:assert')
const { loadPluginJs } = require('./lib/loadPluginJs.js')

const S = loadPluginJs('Store.js', [
  'emptyDoc', 'normalizeDoc', 'setProfile', 'setSetting',
  'markIssue', 'archiveIssues', 'pruneArchive', 'clearComicData', 'setConnection'
])

const ISSUES = [{ id: '1', title: 'A' }, { id: '2', title: 'B' }]

test('emptyDoc has no default profile and sane settings', () => {
  const doc = S.emptyDoc()
  assert.equal(doc.profile.username, '')
  assert.equal(doc.settings.storeDataLocally, true)
  assert.equal(doc.settings.archivePulls, false)
  assert.deepEqual(doc.cache, { weekKey: '', fetchedMs: 0, issues: [] })
})

test('normalizeDoc survives garbage input', () => {
  for (const bad of [null, undefined, 'x', 42, [], { profile: 'no', settings: [], marks: 'no' }]) {
    const doc = S.normalizeDoc(bad)
    assert.equal(doc.profile.username, '')
    assert.equal(doc.settings.source, 'pulls')
    assert.deepEqual(doc.marks, {})
  }
})

test('normalizeDoc clamps refresh interval and normalizes enums', () => {
  let doc = S.normalizeDoc({ settings: { refreshIntervalMin: 5, source: 'bogus', viewMode: 'grid' } })
  assert.equal(doc.settings.refreshIntervalMin, 10)
  assert.equal(doc.settings.source, 'pulls')
  assert.equal(doc.settings.viewMode, 'grid')

  doc = S.normalizeDoc({ settings: { refreshIntervalMin: '45' } })
  assert.equal(doc.settings.refreshIntervalMin, 45)

  doc = S.normalizeDoc({ settings: { refreshIntervalMin: 99999 } })
  assert.equal(doc.settings.refreshIntervalMin, 720)
})

test('markIssue merges facets and garbage-collects empty entries', () => {
  let doc = S.emptyDoc()
  doc = S.markIssue(doc, '111', { collected: true })
  assert.deepEqual(doc.marks['111'], { collected: true })

  doc = S.markIssue(doc, '111', { readAt: 1234 })
  assert.deepEqual(doc.marks['111'], { collected: true, readAt: 1234 })

  doc = S.markIssue(doc, '111', { wishlist: true, collected: false })
  assert.deepEqual(doc.marks['111'], { readAt: 1234, wishlist: true })

  doc = S.markIssue(doc, '111', { readAt: 0, wishlist: false })
  assert.ok(!('111' in doc.marks))
})

test('archiveIssues is gated by the enabled flag and key format', () => {
  let doc = S.emptyDoc()
  doc = S.archiveIssues(doc, '2026-08-26', ISSUES, {})
  assert.deepEqual(doc.archive, {})

  doc = S.archiveIssues(doc, 'not-a-key', ISSUES, { enabled: true })
  assert.deepEqual(doc.archive, {})

  doc = S.archiveIssues(doc, '2026-08-26', ISSUES, { enabled: true })
  assert.equal(doc.archive['2026-08-26'].issues.length, 2)
})

test('pruneArchive keeps the newest weeks only', () => {
  let doc = S.emptyDoc()
  const weeks = ['2026-06-03', '2026-07-01', '2026-08-26', '2026-08-19']
  for (const w of weeks) doc = S.archiveIssues(doc, w, ISSUES, { enabled: true })
  doc = S.pruneArchive(doc, 2)
  assert.deepEqual(Object.keys(doc.archive).sort(), ['2026-08-19', '2026-08-26'])
})

test('connection clearance persists and clears', () => {
  let doc = S.emptyDoc()
  assert.equal(doc.connection.clearance, '')
  doc = S.setConnection(doc, ' tok-en ', ' Mozilla/5.0 X11 ')
  assert.equal(doc.connection.clearance, 'tok-en')
  assert.equal(doc.connection.userAgent, 'Mozilla/5.0 X11')
  const roundTripped = S.normalizeDoc(JSON.parse(JSON.stringify(doc)))
  assert.deepEqual(roundTripped.connection, doc.connection)
  doc = S.setConnection(doc, '', '')
  assert.deepEqual(doc.connection, { clearance: '', userAgent: '' })
})

test('clearComicData wipes fetched data but keeps user data', () => {
  let doc = S.emptyDoc()
  doc = S.setProfile(doc, 'alice', 1000)
  doc = S.markIssue(doc, '9', { wishlist: true })
  doc = S.setSetting(doc, 'viewMode', 'grid')
  doc = S.archiveIssues(doc, '2026-08-26', ISSUES, { enabled: true })
  doc.cache = { weekKey: '2026-08-26', fetchedMs: 5, issues: ISSUES }

  doc = S.clearComicData(doc)
  assert.deepEqual(doc.archive, {})
  assert.deepEqual(doc.cache, { weekKey: '', fetchedMs: 0, issues: [] })
  assert.equal(doc.profile.username, 'alice')
  assert.equal(doc.settings.viewMode, 'grid')
  assert.deepEqual(doc.marks['9'], { wishlist: true })
})

test('documents survive a JSON round trip unchanged', () => {
  let doc = S.emptyDoc()
  doc = S.setProfile(doc, 'alice', 7)
  doc = S.markIssue(doc, '5', { collected: true, readAt: 9 })
  doc = S.archiveIssues(doc, '2026-08-26', ISSUES, { enabled: true })

  const roundTripped = S.normalizeDoc(JSON.parse(JSON.stringify(doc)))
  assert.deepEqual(roundTripped, doc)
})
