// Model.js test suite. Run with: node --test tests/
// Sets UTC so date-label assertions are deterministic regardless of host TZ.
'use strict'
process.env.TZ = 'UTC'

const test = require('node:test')
const assert = require('node:assert')
const fs = require('node:fs')
const path = require('node:path')
const { loadPluginJs } = require('./lib/loadPluginJs.js')

const M = loadPluginJs('Model.js', [
  'decodeEntities', 'cleanText', 'parseReleases', 'filterIssues',
  'weekLabel', 'formatPulls', 'feedUrl', 'daysUntil',
  'ymdParts', 'weekKeyOf', 'shiftWeekTs', 'ymdPath', 'diagnose'
])

const fixture = (name) => fs.readFileSync(path.join(__dirname, 'fixtures', name), 'utf8')

// Anchor used by LoCG for the week of Aug 26 2026 (captured live).
const ANCHOR_MS = 1787716800 * 1000

test('cleanText decodes entities and collapses whitespace', () => {
  assert.equal(M.cleanText('  Foo&nbsp;&amp;&#8217;s\tBar\n '), 'Foo &\u2019s Bar')
})

test('parseReleases reads every issue block in fixtures', () => {
  assert.equal(M.parseReleases(fixture('releases-current.html')).length, 12)
  assert.equal(M.parseReleases(fixture('releases-past.html')).length, 12)
  assert.equal(M.parseReleases(fixture('pulls-current.html')).length, 7)
})

test('parsed issues carry sane core fields', () => {
  const issues = M.parseReleases(fixture('releases-current.html'))
  const first = issues[0]
  assert.match(first.id, /^\d+$/)
  assert.ok(first.title.length > 0)
  assert.ok(first.url.startsWith('https://leagueofcomicgeeks.com/comic/'))
  assert.ok(first.releaseTs > 0)
})

test('variant rows are flagged via data-parent', () => {
  const html = '<li class="issue row" data-comic="111" data-parent="222" data-pulls="3">' +
    '<a href="/comic/x/111"><div class="title"><a>X</a></div></a>' +
    '<div class="publisher">Marvel</div><span data-date="1787716800">$3.99</span>' +
    '<img data-src="https://d2l7y3te53hjm3.cloudfront.net/covers/a/b.jpg"></li>'
  const issues = M.parseReleases(html)
  assert.equal(issues.length, 1)
  assert.equal(issues[0].isVariant, true)
  assert.equal(issues[0].price, '$3.99')
})

test('filterIssues drops variants and applies query', () => {
  const issues = M.parseReleases(fixture('releases-current.html'))
  const total = issues.length
  const variantCount = issues.filter((i) => i.isVariant).length

  assert.equal(M.filterIssues(issues, { excludeVariants: false }).length, total)
  assert.equal(M.filterIssues(issues, {}).length, total - variantCount)

  const q = M.filterIssues(issues, { query: 'zzz-no-match-zzz' })
  assert.equal(q.length, 0)
})

test('filterIssues honours collection marks', () => {
  const issues = [
    { id: '1', title: 'Alpha', publisher: 'Marvel', isVariant: false },
    { id: '2', title: 'Beta', publisher: 'Marvel', isVariant: false },
    { id: '3', title: 'Gamma', publisher: 'Image', isVariant: false }
  ]
  const marks = {
    '1': { collected: true, readAt: 1000 },
    '3': { wishlist: true }
  }

  assert.equal(M.filterIssues(issues, { marks }).length, 3)
  assert.equal(M.filterIssues(issues, { marks, hideCollected: true }).map(i => i.id).join(), '2,3')
  assert.equal(M.filterIssues(issues, { marks, hideRead: true }).map(i => i.id).join(), '2,3')
  assert.equal(M.filterIssues(issues, { marks, wishlistOnly: true }).map(i => i.id).join(), '3')
})

test('weekLabel renders UTC-deterministic labels under TZ=UTC', () => {
  assert.equal(M.weekLabel(ANCHOR_MS), 'Aug 26')
  assert.equal(M.weekLabel(0), '')
})

test('daysUntil uses explicit clock when provided', () => {
  assert.equal(M.daysUntil(ANCHOR_MS, ANCHOR_MS), 0)
  assert.equal(M.daysUntil(ANCHOR_MS, ANCHOR_MS - 86400000), 1)
  assert.equal(M.daysUntil(ANCHOR_MS, ANCHOR_MS + 86400000), -1)
  assert.equal(M.daysUntil(0), null)
})

test('formatPulls abbreviates thousands', () => {
  assert.equal(M.formatPulls(950), '950')
  assert.equal(M.formatPulls(1200), '1.2k')
  assert.equal(M.formatPulls(25000), '25k')
})

test('weekKeyOf formats ISO keys from epoch ms', () => {
  assert.equal(M.weekKeyOf(ANCHOR_MS), '2026-08-26')
  assert.equal(M.weekKeyOf(0), '')
})

test('shiftWeekTs crosses month boundaries cleanly', () => {
  assert.equal(M.weekKeyOf(M.shiftWeekTs(ANCHOR_MS, -1)), '2026-08-19')
  assert.equal(M.weekKeyOf(M.shiftWeekTs(ANCHOR_MS, -2)), '2026-08-12')
  assert.equal(M.weekKeyOf(M.shiftWeekTs(ANCHOR_MS, 2)), '2026-09-09')
  // Across the 2026 -> 2027 year boundary.
  const dec30 = Date.UTC(2026, 11, 30) / 1000 * 1000
  assert.equal(M.weekKeyOf(M.shiftWeekTs(dec30, -2)), '2026-12-16')
  assert.equal(M.weekKeyOf(M.shiftWeekTs(Date.UTC(2027, 0, 6), -1)), '2026-12-30')
})

test('ymdPath builds zero-padded URL fragments', () => {
  assert.equal(M.ymdPath(ANCHOR_MS), '2026/08/26')
})

test('feedUrl routes sources and week offsets', () => {
  assert.equal(
    M.feedUrl('alice', 'pulls'),
    'https://leagueofcomicgeeks.com/profile/alice/pull-list'
  )
  assert.equal(M.feedUrl('', 'pulls'), 'https://leagueofcomicgeeks.com/comics/new-comics')
  assert.equal(M.feedUrl('alice', 'releases'), 'https://leagueofcomicgeeks.com/comics/new-comics')
  assert.equal(
    M.feedUrl('alice', 'releases', ANCHOR_MS, -2),
    'https://leagueofcomicgeeks.com/comics/new-comics/2026/08/12'
  )
  // Offset 0 keeps the cheap canonical URL.
  assert.equal(
    M.feedUrl('alice', 'releases', ANCHOR_MS, 0),
    'https://leagueofcomicgeeks.com/comics/new-comics'
  )
  // Pull lists never get dated URLs anonymously.
  assert.equal(
    M.feedUrl('alice', 'pulls', ANCHOR_MS, -2),
    'https://leagueofcomicgeeks.com/profile/alice/pull-list'
  )
})

test('diagnose classifies captured responses', () => {
  assert.deepEqual(M.diagnose(fixture('releases-current.html')), { status: 'ok', count: 12 })
  assert.deepEqual(M.diagnose(fixture('releases-past.html')), { status: 'ok', count: 12 })
  assert.deepEqual(M.diagnose(fixture('pulls-current.html')), { status: 'ok', count: 7 })
  assert.equal(M.diagnose(fixture('challenge.html')).status, 'challenge')
  assert.equal(M.diagnose(fixture('broken-markup.html')).status, 'suspect')
  assert.equal(M.diagnose('').status, 'empty')
  assert.equal(M.diagnose('<html></html>').status, 'empty')
})

test('healthy Cloudflare-fronted pages are not mistaken for challenges', () => {
  // Real LoCG profile page: loads Cloudflare assets (cdn-cgi) but is not a
  // challenge. Regression for the cdn-cgi/scripts false positive.
  const real = fixture('profile-page.html')
  assert.ok(real.includes('/cdn-cgi/'))
  const verdict = M.diagnose(real)
  assert.notEqual(verdict.status, 'challenge')
  assert.equal(verdict.status, 'suspect')
})

test('plugin JS stays free of Node globals for the QML engine', () => {
  // Match real usages, not prose mentions inside comments.
  const offenders = [/module\.exports/, /\brequire\s*\(/, /\bexports\s*\./]
  for (const f of ['Model.js', 'Store.js']) {
    const src = fs.readFileSync(path.join(__dirname, '..', f), 'utf8')
    for (const re of offenders) {
      assert.doesNotMatch(src, re, `${f} references Node globals via ${re}`)
    }
  }
})
