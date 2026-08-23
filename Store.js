// Pure state-document helpers for Longbox.
//
// The widget persists one JSON document at
//   ~/.local/state/omarchy/settings/longbox.json
// via a Quickshell FileView (see Panel.qml). This file holds every transform
// on that document so the logic stays testable with Node and free of QML.
//
// Storage model:
//   Always persisted  - profile, settings, marks (tiny user data)
//   Optional          - cache (last-good fetch) + archive (past pull weeks),
//                       governed by settings.storeDataLocally / archivePulls

function emptyDoc() {
  return {
    version: 1,
    profile: { username: "", validatedAt: 0 },
    settings: {
      source: "pulls",
      excludeVariants: true,
      showCovers: true,
      refreshIntervalMin: 60,
      viewMode: "list",
      storeDataLocally: true,
      archivePulls: false
    },
    marks: {},
    archive: {},
    cache: { weekKey: "", fetchedMs: 0, issues: [] },
    // Cloudflare escape hatch: cf_clearance cookie pasted from the user's
    // browser plus the exact User-Agent it was issued to. Both must travel
    // together or Cloudflare rejects the clearance.
    connection: { clearance: "", userAgent: "" }
  }
}

var SETTING_DEFAULTS = emptyDoc().settings

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

// Coerce anything read from disk into a valid document. Unknown keys are
// dropped; bad types fall back to defaults; the version is stamped.
function normalizeDoc(raw) {
  var doc = emptyDoc()
  if (!isPlainObject(raw)) return doc

  if (isPlainObject(raw.profile)) {
    doc.profile.username = String(raw.profile.username || "").trim()
    var v = Number(raw.profile.validatedAt)
    doc.profile.validatedAt = isFinite(v) && v > 0 ? v : 0
  }

  if (isPlainObject(raw.settings)) {
    for (var key in SETTING_DEFAULTS) {
      var def = SETTING_DEFAULTS[key]
      var val = raw.settings[key]
      if (typeof def === "boolean") {
        if (typeof val === "boolean") doc.settings[key] = val
      } else if (key === "refreshIntervalMin") {
        var n = Math.round(Number(val))
        doc.settings[key] = isFinite(n) ? Math.min(720, Math.max(10, n)) : def
      } else if (key === "source") {
        doc.settings[key] = val === "releases" ? "releases" : "pulls"
      } else if (key === "viewMode") {
        doc.settings[key] = val === "grid" ? "grid" : "list"
      } else if (typeof val === "string") {
        doc.settings[key] = val
      }
    }
  }

  if (isPlainObject(raw.marks)) {
    for (var id in raw.marks) {
      var m = raw.marks[id]
      if (!isPlainObject(m)) continue
      var entry = {}
      if (m.collected) entry.collected = true
      if (m.wishlist) entry.wishlist = true
      var rt = Number(m.readAt)
      if (isFinite(rt) && rt > 0) entry.readAt = rt
      // Drop entries that carry no information at all.
      if (entry.collected || entry.wishlist || entry.readAt) doc.marks[id] = entry
    }
  }

  if (isPlainObject(raw.archive)) {
    for (var wk in raw.archive) {
      var a = raw.archive[wk]
      if (!/^\d{4}-\d{2}-\d{2}$/.test(wk) || !isPlainObject(a) || !Array.isArray(a.issues)) continue
      var savedMs = Number(a.savedMs)
      doc.archive[wk] = { issues: a.issues, savedMs: isFinite(savedMs) && savedMs > 0 ? savedMs : 0 }
    }
  }

  if (isPlainObject(raw.cache)) {
    var f = Number(raw.cache.fetchedMs)
    doc.cache.weekKey = String(raw.cache.weekKey || "")
    doc.cache.fetchedMs = isFinite(f) && f > 0 ? f : 0
    if (Array.isArray(raw.cache.issues)) doc.cache.issues = raw.cache.issues
  }

  if (isPlainObject(raw.connection)) {
    doc.connection.clearance = String(raw.connection.clearance || "").trim()
    doc.connection.userAgent = String(raw.connection.userAgent || "").trim()
  }

  return doc
}

function setConnection(doc, clearance, userAgent) {
  var next = normalizeDoc(doc)
  next.connection.clearance = String(clearance || "").trim()
  next.connection.userAgent = String(userAgent || "").trim()
  return next
}

function setProfile(doc, username, validatedAt) {
  var next = normalizeDoc(doc)
  next.profile.username = String(username || "").trim()
  next.profile.validatedAt = validatedAt || 0
  return next
}

function setSetting(doc, key, value) {
  var next = normalizeDoc(doc)
  if (key in next.settings) next.settings[key] = value
  return next
}

// Merge a mark patch for one issue id, e.g. { collected: true } or
// { readAt: Date.now() }. Passing falsy clears that facet. When nothing is
// set anymore the whole entry is removed to keep small docs small.
// Facets: collected (bool), wishlist (bool), readAt (ms timestamp).
function markIssue(doc, id, patch) {
  var next = normalizeDoc(doc)
  var key = String(id || "")
  if (key === "" || !isPlainObject(patch)) return next
  var current = isPlainObject(next.marks[key]) ? next.marks[key] : {}
  var entry = {}

  if (patch.collected !== undefined) current.collected = !!patch.collected
  if (patch.wishlist !== undefined) current.wishlist = !!patch.wishlist
  if (patch.readAt !== undefined) current.readAt = patch.readAt || 0

  if (current.collected) entry.collected = true
  if (current.wishlist) entry.wishlist = true
  if (current.readAt) entry.readAt = current.readAt

  if (entry.collected || entry.wishlist || entry.readAt) next.marks[key] = entry
  else delete next.marks[key]
  return next
}

// Snapshot a fetched pull week into the archive. Gated: only writes when
// options.enabled is true (the caller resolves both storage toggles).
function archiveIssues(doc, weekKey, issues, options) {
  var opts = options || {}
  var next = normalizeDoc(doc)
  if (!opts.enabled || !/^\d{4}-\d{2}-\d{2}$/.test(String(weekKey || ""))) return next
  if (!Array.isArray(issues) || issues.length === 0) return next
  next.archive[weekKey] = { issues: issues, savedMs: Date.now() }
  return next
}

// Keep only the newest maxWeeks archived weeks (keys are ISO dates, so
// lexicographic order is chronological).
function pruneArchive(doc, maxWeeks) {
  var next = normalizeDoc(doc)
  var limit = Math.max(1, Number(maxWeeks) || 26)
  var keys = []
  for (var k in next.archive) keys.push(k)
  keys.sort()
  while (keys.length > limit) {
    delete next.archive[keys.shift()]
  }
  return next
}

// Wipe everything derived from fetching (cache + archive). Profile,
// settings, and marks are intentionally preserved. Used when the user turns
// local data storage off.
function clearComicData(doc) {
  var next = normalizeDoc(doc)
  next.archive = {}
  next.cache = emptyDoc().cache
  return next
}
