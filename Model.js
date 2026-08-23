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
// reference their parent via data-parent="<comicId>".
function parseReleases(html) {
  var issues = []
  if (!html || html.indexOf("<li") < 0) return issues
  var blockRe = /<li class="issue[^"]*"[^>]*>([\s\S]*?)<\/li>/g
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

    var publisherMatch = /class="publisher[^"]*">([\s\S]*?)<\/div>/.exec(body)
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

// Build the fetch URL for a LoCG source.
// NOTE: Only the un-dated profile page serves pull-list data publicly;
// dated URLs (/pull-list/YYYY/MM/DD) return empty lists without a login
// session. Releases pages, however, serve any week publicly at
// /comics/new-comics/YYYY/MM/DD (verified 2026-08), so week navigation is
// anchored to a server-provided week timestamp and only releases fetches
// get dated URLs.
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

// NOTE: This file must not reference undeclared globals (e.g. `module`):
// QML's JS engine throws ReferenceError at script-evaluation time for them.
// For Node-based tests, use the loader in tests/lib/loadPluginJs.js.
