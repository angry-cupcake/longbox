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
  'ymdParts', 'weekKeyOf', 'shiftWeekTs', 'ymdPath', 'diagnose',
  'ajaxUrl', 'parseAjaxEnvelope', 'parseAjaxList', 'classifyAjax',
  'extractProfileUserId', 'looksAnonymousPull', 'extractCiSession', 'loginErrorFromHtml',
  'currentWeekTs', 'isSizeOverflow', 'transferFailed', 'RESPONSE_BYTE_LIMIT'
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

// --------------------------------------------------------------- AJAX endpoint

const ajaxEnvelope = (name) => fixture(`ajax-${name}.json`)

test('parseReleases reads the AJAX attribute order', () => {
  // Real get_comics rows: <li id="comic-N" class="issue" ...> (id first).
  const issues = M.parseAjaxList(ajaxEnvelope('releases'))
  assert.equal(issues.length, 12)
  assert.match(issues[0].id, /^\d+$/)
  assert.ok(issues[0].title.length > 0)
  assert.ok(issues[0].releaseTs > 0)
})

test('real authenticated pull rows parse clean fields', () => {
  // Captured from a signed-in dated pull fetch. Publisher lives in a span
  // here (div on pages) - regression for swallowed date/price markup.
  const issues = M.parseAjaxList(ajaxEnvelope('pulls-auth'))
  assert.equal(issues.length, 6)
  for (const i of issues) {
    assert.ok(!/[<>]/.test(i.title), 'title must not leak HTML: ' + i.title)
    assert.ok(!/[<>]/.test(i.publisher), 'publisher must not leak HTML: ' + i.publisher)
    assert.match(i.price, /^\$\d/)
    assert.ok(i.releaseTs > 0)
  }
  assert.ok(issues.some((i) => i.publisher === 'DC Comics'))
  assert.ok(issues.some((i) => i.publisher === 'Marvel Comics'))
})

test('parseReleases handles both attribute orders in one document', () => {
  const html =
    '<li id="comic-1" class="issue " data-comic="1" data-parent="0" data-pulls="9">' +
    '<a href="/comic/x/1"><div class="title"><a>Ajax One</a></div></a>' +
    '<div class="publisher">Marvel</div><span data-date="1787716800">$3.99</span></li>' +
    '<li class="issue row" data-comic="2" data-parent="0" data-pulls="8">' +
    '<a href="/comic/x/2"><div class="title"><a>Page Two</a></div></a>' +
    '<div class="publisher">DC</div><span data-date="1787716800">$4.99</span></li>'
  const issues = M.parseReleases(html)
  assert.equal(issues.length, 2)
  assert.deepEqual(issues.map((i) => i.title), ['Ajax One', 'Page Two'])
})

test('classifyAjax verdicts across captured responses', () => {
  assert.deepEqual(M.classifyAjax(ajaxEnvelope('releases')), { status: 'ok', count: 12 })
  assert.deepEqual(M.classifyAjax(ajaxEnvelope('pulls-auth')), { status: 'ok', count: 6 })
  // Empty weeks and anonymous pull lists are valid, just empty.
  assert.deepEqual(M.classifyAjax(ajaxEnvelope('empty-pulls')), { status: 'nolists', count: 0 })
  assert.deepEqual(M.classifyAjax(ajaxEnvelope('anon-pulls')), { status: 'nolists', count: 0 })
  assert.deepEqual(M.classifyAjax(fixture('challenge.html')).status, 'challenge')
  assert.deepEqual(M.classifyAjax(''), { status: 'empty', count: 0 })
  // Bytes but not an envelope: proxy error pages, truncated bodies.
  assert.deepEqual(M.classifyAjax('<html><body>gateway timeout</body></html>').status, 'suspect')
  assert.deepEqual(M.classifyAjax('{"count":3,"list":"no li here"}').status, 'suspect')
})

test('parseAjaxList is safe on every input shape', () => {
  assert.deepEqual(M.parseAjaxList(null), [])
  assert.deepEqual(M.parseAjaxList(undefined), [])
  assert.deepEqual(M.parseAjaxList(''), [])
  assert.deepEqual(M.parseAjaxList('garbage{'), [])
  assert.deepEqual(M.parseAjaxList('{"list":123}'), [])
})

test('response byte cap is finite and generous for real LoCG pages', () => {
  assert.ok(M.RESPONSE_BYTE_LIMIT >= 1024 * 1024, 'must not clip real pages')
  assert.ok(M.RESPONSE_BYTE_LIMIT <= 16 * 1024 * 1024, 'must actually bound memory')
})

test('isSizeOverflow flags only the curl byte-cap exit code', () => {
  assert.equal(M.isSizeOverflow(63), true)
  assert.equal(M.isSizeOverflow('63'), true)
  // Success, timeout, network failure: normal classification paths.
  assert.equal(M.isSizeOverflow(0), false)
  assert.equal(M.isSizeOverflow(28), false)
  assert.equal(M.isSizeOverflow(56), false)
  assert.equal(M.isSizeOverflow(undefined), false)
  assert.equal(M.isSizeOverflow(null), false)
})

test('transferFailed flags every nonzero exit code', () => {
  assert.equal(M.transferFailed(0), false)
  assert.equal(M.transferFailed(28), true)   // timeout
  assert.equal(M.transferFailed(6), true)    // could not resolve host
  assert.equal(M.transferFailed(63), true)   // byte cap (also caught upstream)
  assert.equal(M.transferFailed('7'), true)
  assert.equal(M.transferFailed(undefined), true) // missing code cannot be trusted
})

test('extractProfileUserId reads the id off a public profile page', () => {
  // Real captured pull-list page (CupcakeIsAngry).
  assert.equal(M.extractProfileUserId(fixture('profile-pull-list.html')), 591452)
  assert.equal(M.extractProfileUserId('<html>nothing here</html>'), 0)
  assert.equal(M.extractProfileUserId(''), 0)
})

test('looksAnonymousPull spots the anonymous zero state', () => {
  // Feed the same shape production sees: the decoded list fragment from an
  // envelope (fixture files store it JSON-escaped).
  const list = (name) => JSON.parse(ajaxEnvelope(name)).list
  // Anonymous/expired pull answer: first-person message + data-user 0.
  assert.equal(M.looksAnonymousPull(list('anon-pulls')), true)
  // Signed-in-but-empty weeks address the user by name instead.
  assert.equal(M.looksAnonymousPull(list('empty-pulls')), false)
  assert.equal(M.looksAnonymousPull(list('pulls-auth')), false)
  assert.equal(M.looksAnonymousPull(list('releases')), false)
  assert.equal(M.looksAnonymousPull(''), false)
})

test('ajaxUrl routes sources, users, and week offsets', () => {
  const base = 'https://leagueofcomicgeeks.com/comic/get_comics?'
  // The API never resolves the current week alone (missing date = epoch
  // week), so every URL is dated. Fresh anchors are used as-is...
  assert.equal(
    M.ajaxUrl('releases', 0, ANCHOR_MS, 0, ANCHOR_MS),
    base + 'list=releases&list_option=thumbs&view=list&date=2026-08-26&date_type=week'
  )
  assert.equal(
    M.ajaxUrl('releases', 0, ANCHOR_MS, -2, ANCHOR_MS),
    base + 'list=releases&list_option=thumbs&view=list&date=2026-08-12&date_type=week'
  )
  // ...stale ones fall back to the computed current Wednesday.
  const sunday = Date.UTC(2026, 7, 23) // Aug 23 2026, before release day
  assert.equal(M.weekKeyOf(M.currentWeekTs(sunday)), '2026-08-26')
  assert.equal(
    M.ajaxUrl('releases', 0, ANCHOR_MS, 0, sunday + 20 * 86400000),
    base + 'list=releases&list_option=thumbs&view=list&date=' +
      M.weekKeyOf(M.currentWeekTs(sunday + 20 * 86400000)) + '&date_type=week'
  )
  // Signed-in pulls carry the user id.
  assert.equal(
    M.ajaxUrl('pulls', 591452, ANCHOR_MS, 0, ANCHOR_MS),
    base + 'list=1&list_option=thumbs&view=list&user_id=591452&date=2026-08-26&date_type=week'
  )
  assert.equal(
    M.ajaxUrl('pulls', 591452, ANCHOR_MS, -1, ANCHOR_MS),
    base + 'list=1&list_option=thumbs&view=list&user_id=591452&date=2026-08-19&date_type=week'
  )
  // A zero/negative user id falls back to the public releases list.
  assert.match(M.ajaxUrl('pulls', 0, ANCHOR_MS, 0, ANCHOR_MS), /list=releases/)
})

test('currentWeekTs lands on the Wednesday-dated week', () => {
  // Sunday -> upcoming Wednesday.
  assert.equal(M.weekKeyOf(M.currentWeekTs(Date.UTC(2026, 7, 23))), '2026-08-26')
  // Wednesday itself is day one of its own week.
  assert.equal(M.weekKeyOf(M.currentWeekTs(ANCHOR_MS)), '2026-08-26')
  // Thursday still belongs to the week that started yesterday.
  assert.equal(M.weekKeyOf(M.currentWeekTs(Date.UTC(2026, 7, 27))), '2026-08-26')
  // Tuesday rolls forward to the next Wednesday.
  assert.equal(M.weekKeyOf(M.currentWeekTs(Date.UTC(2026, 7, 25))), '2026-08-26')
  // Year boundary: Wed Dec 30 2026 week, viewed Jan 1 2027.
  assert.equal(M.weekKeyOf(M.currentWeekTs(Date.UTC(2027, 0, 1))), '2026-12-30')
})

test('extractCiSession finds the session cookie in header dumps', () => {
  const dump = [
    'HTTP/1.1 302 Found',
    'Set-Cookie: ci_session=a1b2c3; expires=Tue, 22-Sep-2026; path=/',
    'Set-Cookie: other=zz; path=/',
    '',
    'HTTP/1.1 200 OK',
    'Content-Type: text/html'
  ].join('\r\n')
  assert.equal(M.extractCiSession(dump), 'a1b2c3')
  assert.equal(M.extractCiSession('HTTP/1.1 200 OK\r\n\r\nbody'), '')
  assert.equal(M.extractCiSession(''), '')
})

test('loginErrorFromHtml extracts the alert block', () => {
  const err = M.loginErrorFromHtml(fixture('login-error.html'))
  // Real LoCG failure copy, captured live (a failed login also grants a
  // guest ci_session - Panel checks the error before trusting any cookie).
  assert.match(err, /Invalid Username and\/or Password/)
  assert.equal(M.loginErrorFromHtml(fixture('releases-current.html')), '')
})
