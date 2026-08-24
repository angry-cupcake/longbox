// Pure data shaping for the Comic Releases widget.
// Parses League of Comic Geeks "New Comics this week" HTML into issue objects
// and computes derived values. Free of QML globals so it can be tested with Node.

function decodeEntities(text) {
  return String(text === undefined || text === null ? "" : text)
    .replace(/&nbsp;/g, " ")
    .replace(/&#183;/g, "\u00b7")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, "\"")
    .replace(/&#0?39;/g, "'")
    .replace(/&#8217;/g, "\u2019")
    .replace(/&#8216;/g, "\u2018")
    .replace(/&#8220;/g, "\u201c")
    .replace(/&#8221;/g, "\u201d")
}

function cleanText(value) {
  return decodeEntities(String(value === undefined || value === null ? "" : value))
    .replace(/[\t\r\n]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
}

// Parse the new-comics listing HTML into an array of issue objects.
// Non-variant issues carry data-parent="0"; variants are collapsed rows that
// reference their parent via data-parent="<comicId>". Rows come in two
// attribute orders: full pages emit <li class="issue" ...> while the AJAX
// get_comics endpoint emits <li id="comic-<id>" class="issue" ...>.
function parseReleases(html) {
  var issues = []
  if (!html || html.indexOf("<li") < 0) return issues
  var blockRe = /<li(?=[^>]*class="issue)[^>]*>([\s\S]*?)<\/li>/g
  var m
  while ((m = blockRe.exec(html)) !== null) {
    var openTag = m[0].slice(0, m[0].indexOf(">") + 1)
    var body = m[1]

    var idAttr = /data-comic="(\d+)"/.exec(openTag)
    if (!idAttr) continue
    var parentAttr = /data-parent="(\d+)"/.exec(openTag)
    var pullsAttr = /data-pulls="(\d+)"/.exec(openTag)

    var linkMatch = /<a href="(\/comic\/[^"]+)"/.exec(body)
    if (!linkMatch) continue

    var titleMatch = /class="title[^"]*"[^>]*>\s*<a[^>]*>([\s\S]*?)<\/a>/.exec(body)
    if (!titleMatch) continue

    // Publisher text is plain; stop at the first tag close. The container
    // differs between surfaces (div on pages, span on API lists).
    var publisherMatch = /class="publisher[^"]*">\s*([^<]+)/.exec(body)
    var dateMatch = /data-date="(-?\d+)"/.exec(body)
    var priceMatch = /\$\s?([\d.]+)/.exec(body)
    var coverMatch = /data-src="([^"]+\/covers\/[^"]+)"/.exec(body)

    issues.push({
      id: idAttr[1],
      isVariant: parentAttr && parentAttr[1] !== "0",
      title: cleanText(titleMatch[1]),
      publisher: publisherMatch ? cleanText(publisherMatch[1]) : "",
      url: "https://leagueofcomicgeeks.com" + cleanText(linkMatch[1]),
      price: priceMatch ? "$" + priceMatch[1] : "",
      releaseTs: dateMatch ? Number(dateMatch[1]) * 1000 : 0,
      pulls: pullsAttr ? Number(pullsAttr[1]) : 0,
      cover: coverMatch ? cleanText(coverMatch[1]) : ""
    })
  }
  return issues
}

function filterIssues(issues, options) {
  options = options || {}
  var excludeVariants = options.excludeVariants !== false
  var publishers = (options.publishers || "")
    .split(",").map(function(p) { return p.trim().toLowerCase() }).filter(function(p) { return p !== "" })
  var query = (options.query || "").trim().toLowerCase()
  // Local collection marks, keyed by issue id: { collected, wishlist, readAt }.
  var marks = options.marks || {}
  return issues.filter(function(issue) {
    if (excludeVariants && issue.isVariant) return false
    if (publishers.length > 0 && publishers.indexOf(issue.publisher.toLowerCase()) < 0) return false
    if (query !== "" && (issue.title + " " + issue.publisher).toLowerCase().indexOf(query) < 0) return false
    var m = marks[issue.id]
    if (options.wishlistOnly && !(m && m.wishlist)) return false
    if (options.hideCollected && m && m.collected) return false
    if (options.hideRead && m && m.readAt) return false
    return true
  })
}

// The release week label, e.g. "Aug 26". LoCG weeks are Wednesday-dated.
function weekLabel(releaseTs) {
  if (!releaseTs) return ""
  var d = new Date(releaseTs)
  if (isNaN(d.getTime())) return ""
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return months[d.getMonth()] + " " + d.getDate()
}

function formatPulls(count) {
  if (count >= 1000) {
    var k = Math.round(count / 100) / 10
    return String(k >= 10 ? Math.round(k) : k.toFixed(1)).replace(/\.0$/, "") + "k"
  }
  return String(count)
}

// Build the fetch URL for the anonymous HTML surfaces: a public profile's
// pull-list page, or the weekly release sheet. These pages resolve the
// current week on their own, and dated release URLs serve any week.
// NOTE: dated profile pages return empty lists without a login session -
// anonymous pulls can only ever see the current week. Signed-in users get
// dated pull lists from ajaxUrl() instead of this scraper.
function feedUrl(username, source, anchorTsMs, weekOffset) {
  var user = cleanText(username)
  if (source !== "releases" && user !== "")
    return "https://leagueofcomicgeeks.com/profile/" + encodeURIComponent(user) + "/pull-list"
  if (anchorTsMs && weekOffset)
    return "https://leagueofcomicgeeks.com/comics/new-comics/" + ymdPath(shiftWeekTs(anchorTsMs, weekOffset))
  return "https://leagueofcomicgeeks.com/comics/new-comics"
}

// Days until (or since) release. Negative means already out.
function daysUntil(releaseTs, nowMs) {
  if (!releaseTs) return null
  var now = nowMs === undefined ? Date.now() : nowMs
  return Math.ceil((releaseTs - now) / 86400000)
}

// ---------------------------------------------------------------------------
// Week math and URL building. All arithmetic is UTC-based: LoCG week
// timestamps are epoch seconds for Wednesday-dated weeks, and offsetting by
// whole days in ms keeps the same time-of-day across DST boundaries.
// ---------------------------------------------------------------------------

function pad2(n) {
  return (n < 10 ? "0" : "") + n
}

// UTC calendar parts of an epoch-ms timestamp as zero-padded strings.
function ymdParts(tsMs) {
  var d = new Date(tsMs)
  return {
    y: String(d.getUTCFullYear()),
    m: pad2(d.getUTCMonth() + 1),
    d: pad2(d.getUTCDate())
  }
}

// Canonical archive/cache key for a week, e.g. "2026-08-26".
function weekKeyOf(tsMs) {
  if (!tsMs) return ""
  var p = ymdParts(tsMs)
  return p.y + "-" + p.m + "-" + p.d
}

// Move an anchored week by whole weeks.
function shiftWeekTs(anchorTsMs, weeks) {
  return anchorTsMs + weeks * 7 * 86400000
}

// YYYY/MM/DD path fragment used by dated new-comics URLs.
function ymdPath(tsMs) {
  var p = ymdParts(tsMs)
  return p.y + "/" + p.m + "/" + p.d
}

// ---------------------------------------------------------------------------
// Response trust boundary
// ---------------------------------------------------------------------------

// Hard ceiling for any single remote response, enforced producer-side by
// curl's --max-filesize flag (curl aborts mid-transfer once received bytes
// exceed the limit, even when no Content-Length was announced - behaviour
// reliable since curl 8.4). Far above any real LoCG page; exists only so a
// compromised or hostile upstream cannot balloon the long-lived shell's
// memory before parsing starts.
var RESPONSE_BYTE_LIMIT = 2 * 1024 * 1024

// True when a transfer died because it hit RESPONSE_BYTE_LIMIT (curl exit
// code 63, CURLE_FILESIZE_EXCEEDED). Whatever reached the collector is
// truncated mid-tag/mid-record: callers must fail closed, never parse it.
function isSizeOverflow(exitCode) {
  return Number(exitCode) === 63
}

// True when the transfer itself failed (timeout, DNS, reset, truncated by
// the byte cap, ...). Partial output may still be parseable - callers must
// refuse it rather than classify whatever fragments arrived.
function transferFailed(exitCode) {
  return Number(exitCode) !== 0
}

// Classify a fetched response before trusting it.
//   ok         - parsed at least one issue
//   challenge  - Cloudflare interstitial ("Just a moment..."); retry may help
//   empty      - no meaningful HTML came back (offline proxy page, timeout body)
//   suspect    - page loaded but zero issues parsed; either a genuinely empty
//                week or LoCG changed their markup. Callers must say both in UI copy.
function diagnose(html) {
  var text = String(html === undefined || html === null ? "" : html)
  var count = parseReleases(text).length
  // Challenge-only markers: the interstitial title and Cloudflare's private
  // challenge state variables. Generic cdn-cgi asset paths appear on every
  // healthy Cloudflare-fronted page and must NOT count as challenges.
  if (/<title>\s*(just a moment|attention required)[^<]*<\/title>/i.test(text) ||
      /(_cf_chl|cf_chl_)[a-z_]*/i.test(text))
    return { status: "challenge", count: count }
  if (!/<title>/i.test(text) || text.length < 500)
    return { status: "empty", count: count }
  if (count > 0)
    return { status: "ok", count: count }
  return { status: "suspect", count: 0 }
}

// ---------------------------------------------------------------------------
// AJAX endpoint (undocumented). The site's own web UI populates its lists by
// calling /comic/get_comics, which answers with a JSON envelope:
//   { count: <n>, list: "<div id='comic-list-block'...><li ...>...</li>...",
//     configurator: { echoed params, incl. user_id }, statbar, filters_* }
// Releases work anonymously. Pull lists (list=1) are session-gated: without
// a ci_session cookie the server ignores user_id and echoes user_id 0.
// ---------------------------------------------------------------------------

// Build a get_comics URL.
//   source "pulls" + userId > 0  -> the signed-in user's pull list
//   anything else                -> the public weekly release sheet
// Unlike the HTML pages, the API does NOT resolve "current week" on its own:
// a missing date param falls back to the epoch week. Always send one - the
// cached anchor when it is fresh enough to trust, otherwise the computed
// Wednesday-dated week containing now.
function ajaxUrl(source, userId, anchorTsMs, weekOffset, nowMs) {
  var params = ""
  var uid = Math.floor(Number(userId) || 0)
  if (source === "pulls" && uid > 0)
    params = "list=1&list_option=thumbs&view=list&user_id=" + encodeURIComponent(String(uid))
  else
    params = "list=releases&list_option=thumbs&view=list"
  var off = Math.floor(Number(weekOffset) || 0)
  var now = Number(nowMs) || 0 || Date.now()
  var base = (anchorTsMs && Math.abs(now - anchorTsMs) < 6 * 86400000)
    ? anchorTsMs
    : currentWeekTs(now)
  params += "&date=" + weekKeyOf(shiftWeekTs(base, off)) + "&date_type=week"
  return "https://leagueofcomicgeeks.com/comic/get_comics?" + params
}

// Epoch-ms of the Wednesday-dated release week that `nowMs` falls into,
// UTC-based like all other week math here. Weeks run Sunday to Saturday but
// carry the Wednesday label: on Sunday Aug 23 the site already shows the
// Aug 26 sheet, and Thursday Aug 27 still belongs to it.
function currentWeekTs(nowMs) {
  var d = new Date(nowMs === undefined ? Date.now() : nowMs)
  var utcDay = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()))
  return utcDay.getTime() - utcDay.getUTCDay() * 86400000 + 3 * 86400000
}

// Parse a get_comics JSON envelope. Returns null for anything that is not
// an envelope-shaped object (HTML pages, challenge interstitials, garbage).
function parseAjaxEnvelope(text) {
  var raw = String(text === undefined || text === null ? "" : text).trim()
  if (raw === "" || raw.charAt(0) !== "{") return null
  try {
    var env = JSON.parse(raw)
    if (env && typeof env.list === "string") return env
  } catch (e) { /* not JSON */ }
  return null
}

// Issues from a get_comics response body. Safe on every input.
function parseAjaxList(text) {
  var env = parseAjaxEnvelope(text)
  return env ? parseReleases(env.list) : []
}

// Classify a get_comics response before trusting it. Mirrors diagnose():
//   ok      - parsed at least one issue
//   nolists - valid envelope, zero issues (empty week or empty pull list)
//   suspect - envelope claims issues exist but none parsed (markup drift),
//             or the endpoint answered with something that is not JSON
//   challenge - Cloudflare interstitial
//   empty   - nothing meaningful came back
function classifyAjax(text) {
  var raw = String(text === undefined || text === null ? "" : text)
  if (raw.trim() === "") return { status: "empty", count: 0 }
  if (/<title>\s*(just a moment|attention required)[^<]*<\/title>/i.test(raw) ||
      /(_cf_chl|cf_chl_)[a-z_]*/i.test(raw))
    return { status: "challenge", count: 0 }
  var env = parseAjaxEnvelope(raw)
  if (!env) return { status: "suspect", count: 0 }
  var parsed = parseReleases(env.list)
  var reported = Number(env.count)
  var count = isFinite(reported) && reported > 0 ? reported : parsed.length
  if (parsed.length > 0) return { status: "ok", count: parsed.length }
  if (count > 0) return { status: "suspect", count: count }
  return { status: "nolists", count: 0 }
}

// Which user does the server think is asking? Unreliable: the echo follows
// request parameters (and cache state), not the session - verified to differ
// between identical anonymous requests. Do not use for auth decisions.

// Numeric id from a public profile page's comic-list-block. Used after
// sign-in to learn the account id for API calls.
function extractProfileUserId(html) {
  var text = String(html === undefined || html === null ? "" : html)
  var m = /id="comic-list-block"[^>]*data-user="(\d+)"/.exec(text)
  if (!m) m = /data-user="(\d+)"/.exec(text)
  return m ? Number(m[1]) : 0
}

// Signature of an anonymous pull-list answer: first-person zero state plus
// a data-user of 0. Together they mean the server ignored our session.
function looksAnonymousPull(text) {
  var raw = String(text === undefined || text === null ? "" : text)
  return /You don&#39;t have any comics pulled|You don't have any comics pulled/i.test(raw) &&
    /data-user="0"/.test(raw)
}

// Pull the ci_session cookie out of a `curl -i` header dump. Redirect chains
// produce several header blocks; the first Set-Cookie that grants a session
// wins.
function extractCiSession(responseText) {
  var re = /set-cookie:\s*ci_session=([^;\r\n]+)/gi
  var m
  while ((m = re.exec(String(responseText === undefined || responseText === null ? "" : responseText))) !== null) {
    var value = m[1].trim()
    if (value !== "") return value
  }
  return ""
}

// Human-readable failure from a login page body ("Invalid username or
// password..."). Empty string means no error block was found.
function loginErrorFromHtml(bodyText) {
  var m = /class="[^"]*alert-error[^"]*"[^>]*>([\s\S]*?)<\/div>/.exec(
    String(bodyText === undefined || bodyText === null ? "" : bodyText))
  return m ? cleanText(m[1].replace(/<[^>]+>/g, " ")) : ""
}

// NOTE: This file must not reference undeclared globals (e.g. `module`):
// QML's JS engine throws ReferenceError at script-evaluation time for them.
// For Node-based tests, use the loader in tests/lib/loadPluginJs.js.
