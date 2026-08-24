import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Store.js" as Store

Panel {
  id: root
  moduleName: "angry-cupcake.longbox"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  // --------------------------------------------------------------- state doc
  // Single persisted document. shell.json seeds a fresh doc; afterwards the
  // doc wins. See Store.js for the schema.
  property var doc: Store.normalizeDoc(null)
  readonly property bool storageEnabled: doc.settings.storeDataLocally === true
  readonly property bool archiveEnabled: storageEnabled && doc.settings.archivePulls === true
  readonly property int archivedWeekCount: Object.keys(doc.archive).length
  readonly property bool isListView: doc.settings.viewMode !== "grid"

  // Effective preferences (doc first, shell.json seed as fallback).
  readonly property string username: {
    var u = String(doc.profile.username || "")
    if (u === "") u = String(setting("username", "") || "")
    return u.trim()
  }
  readonly property string source: doc.settings.source === "releases" ? "releases"
    : (String(setting("source", "")) === "releases" ? "releases" : "pulls")
  readonly property bool excludeVariants: doc.settings.excludeVariants !== false
  readonly property bool showCovers: doc.settings.showCovers !== false
  readonly property int refreshIntervalMs: Math.max(10, Number(doc.settings.refreshIntervalMin) || 360) * 60000

  // ------------------------------------------------------------ panel state
  property string activeTab: needsSetup ? "settings" : "comics"
  property var issues: []
  property string query: ""
  property bool loading: false
  property string loadError: ""
  property double lastSuccessfulMs: 0
  property int weekOffset: 0
  property int fetchExitCode: 0

  // Session-only list filters (reset each open).
  property bool hideCollected: false
  property bool hideRead: false
  property bool wishlistOnly: false

  // True while the current fetch is the automatic second attempt after a
  // Cloudflare challenge; lets finishRefresh decide between retrying and
  // escalating to the browser hand-off message.
  property bool fetchIsRetry: false

  // Profile validation state: null = idle, true/false = result of last check.
  property bool validatingProfile: false
  property bool profileValid: false
  property string profileStatus: ""

  // Opt-in LoCG account session. Only the cookie lives in the doc; the
  // password exists solely inside requestSignIn's call frame.
  readonly property bool signedIn: Store.isSignedIn(doc)
  readonly property string displayUser: signedIn ? doc.account.name : username
  property bool signingIn: false
  property string loginStatus: ""
  property string pendingSession: ""
  property string pendingName: ""

  readonly property bool needsSetup: !signedIn && source === "pulls" && username === ""

  readonly property string httpAgent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"

  readonly property var visibleIssues: Model.filterIssues(issues, {
    excludeVariants: excludeVariants,
    query: query,
    marks: doc.marks,
    hideCollected: hideCollected,
    hideRead: hideRead,
    wishlistOnly: wishlistOnly
  })

  // The bar count is pinned to the live current-week list (the cache), never
  // to whatever historical week happens to be open in the panel.
  readonly property int liveCount: Model.filterIssues(doc.cache.issues, {
    excludeVariants: excludeVariants
  }).length
  readonly property string barCount: needsSetup ? "" : (liveCount > 0 ? String(liveCount) : "")

  // Cookie flags for curl. Values are charset-sanitized in Store.js, so each
  // pair is a single shell-safe word; repeated -b flags merge into one jar.
  function cookieArgs(sessionOverride) {
    var cookies = []
    var clearance = String(doc.connection.clearance || "")
    if (clearance !== "") cookies.push("cf_clearance=" + clearance)
    if (sessionOverride !== undefined) {
      if (sessionOverride !== "") cookies.push("ci_session=" + sessionOverride)
    } else if (signedIn) {
      cookies.push("ci_session=" + doc.account.session)
    }
    var args = []
    for (var i = 0; i < cookies.length; i++) args.push("-b", cookies[i])
    return args
  }

  function curlArgs() {
    return cookieArgs()
  }

  // Route per auth state: signed-in pulls come from the AJAX API for any
  // week; anonymous pulls still scrape the public profile page; releases
  // always use the AJAX endpoint.
  function fetchUrl() {
    if (signedIn) return Model.ajaxUrl("pulls", doc.account.userId, cachedAnchorMs(), weekOffset)
    if (source === "pulls") return Model.feedUrl(username, "pulls", 0, 0)
    return Model.ajaxUrl("releases", 0, cachedAnchorMs(), weekOffset)
  }

  // Human-facing page for the bar widget's right-click "open on LoCG".
  function siteUrl() {
    if (source === "pulls" && displayUser !== "")
      return "https://leagueofcomicgeeks.com/profile/" + encodeURIComponent(displayUser) + "/pull-list"
    return "https://leagueofcomicgeeks.com/comics/new-comics"
  }

  // Server-provided week anchor from the cache, if any (ms, else 0).
  function cachedAnchorMs() {
    for (var i = 0; i < doc.cache.issues.length; i++) {
      var ts = Number(doc.cache.issues[i].releaseTs)
      if (ts > 0) return ts
    }
    return 0
  }

  readonly property string currentWeekKey: {
    for (var i = 0; i < issues.length; i++)
      if (!issues[i].isVariant && issues[i].releaseTs) return Model.weekKeyOf(issues[i].releaseTs)
    return doc.cache.weekKey || ""
  }

  readonly property string weekLabel: {
    for (var i = 0; i < issues.length; i++)
      if (!issues[i].isVariant && issues[i].releaseTs) return Model.weekLabel(issues[i].releaseTs)
    return ""
  }

  function barTooltipText() {
    if (needsSetup) return "Longbox · set up your profile to track pulls"
    var who = source === "pulls" ? displayUser + "'s pull list" : "New comics this week"
    if (weekOffset !== 0) who += " · browsing " + (weekOffset > 0 ? "+" : "") + weekOffset + "w"
    else if (weekLabel !== "") who += " · " + weekLabel
    if (loadError !== "") return who + " (offline)"
    return who
  }
  readonly property string barTooltip: barTooltipText()

  // ------------------------------------------------------------- persistence
  FileView {
    id: stateFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/longbox.json"
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadState(text())
    onLoadFailed: root.loadState("")
  }

  function loadState(raw) {
    var loaded = Store.normalizeDoc(raw)
    if (raw === "") {
      // Fresh install: seed from any hand-set shell.json overrides.
      for (var key in loaded.settings) {
        var v = setting(key, undefined)
        if (v !== undefined) loaded.settings[key] = v
      }
    }
    doc = Store.pruneArchive(loaded, 26)
    // The startup timer usually fires before this async load lands and
    // bails on needsSetup; kick one refresh now that prefs are known.
    Qt.callLater(root.startRefresh)
  }

  function commit(nextDoc) {
    doc = nextDoc
    try {
      stateFile.setText(JSON.stringify(doc))
      ensureStatePerms()
    } catch (e) {
      console.warn("[longbox] state write failed:", e)
    }
  }

  function changeSetting(key, value) {
    commit(Store.setSetting(doc, key, value))
    if (key === "source" || key === "refreshIntervalMin") startRefresh()
  }

  function clearAllComicData() {
    commit(Store.clearComicData(doc))
    issues = []
    loadError = ""
  }

  function clearArchiveOnly() {
    var next = Store.normalizeDoc(doc)
    next.archive = {}
    commit(next)
  }

  // ----------------------------------------------------------------- fetching
  // Cloudflare clearance (and, when signed in, the account session) travel
  // with every request; see cookieArgs() above.

  function startRefresh(isAutoRetry) {
    if (fetchProcess.running) return
    if (needsSetup) return
    loading = true
    fetchIsRetry = isAutoRetry === true
    loadError = ""
    fetchProcess.command = ["/usr/bin/env", "curl", "-sL", "--max-time", "25",
      "--max-filesize", String(Model.RESPONSE_BYTE_LIMIT),
      "-A", root.httpAgent].concat(curlArgs(), [fetchUrl()])
    fetchProcess.running = true
  }

  function finishRefresh() {
    loading = false
    // The byte cap tripped: the collector holds a body cut off mid-tag or
    // mid-record. Refuse it outright instead of letting the classifiers
    // guess at fragments.
    if (Model.isSizeOverflow(fetchExitCode)) {
      fetchIsRetry = false
      loadError = "League of Comic Geeks sent an oversized response - refusing to read it."
      return
    }
    var body = fetchStdout.text
    var usesAjax = signedIn || source === "releases"
    var verdict = usesAjax ? Model.classifyAjax(body) : Model.diagnose(body)

    if (verdict.status === "challenge") {
      // One automatic retry; challenges are often per-request. If it
      // persists, hand the user to the browser + clearance flow.
      if (!fetchIsRetry) {
        loadError = "Bot check detected, retrying..."
        retryTimer.restart()
        return
      }
      loadError = "League of Comic Geeks keeps bot-checking this connection. Open the site in your browser, then paste your clearance cookie in Settings."
      return
    }
    fetchIsRetry = false

    if (verdict.status === "empty" && fetchExitCode !== 0) {
      if (!showArchiveFallback()) loadError = "Could not reach League of Comic Geeks."
      return
    }

    if (usesAjax) finishAjax(verdict, body)
    else finishHtml(verdict, body)
  }

  function finishAjax(verdict, body) {
    // Session liveness: a signed-in pull request answered by the anonymous
    // zero state (data-user 0 + "You don't have any comics pulled") means
    // the cookie expired. Sign out gracefully and refetch anonymously.
    // The API's user echo is unreliable for this - see looksAnonymousPull.
    if (signedIn && source === "pulls" && verdict.status === "nolists"
        && Model.looksAnonymousPull(body)) {
      expireSession()
      return
    }

    var parsed = Model.parseAjaxList(body)
    issues = parsed

    if (verdict.status === "ok") {
      // Only the live current-week fetch updates cache, archive, and the
      // refresh cadence; browsing history must not overwrite them.
      if (weekOffset === 0) {
        lastSuccessfulMs = Date.now()
        saveCache(parsed)
      }
    } else if (verdict.status === "nolists") {
      loadError = signedIn && source === "pulls"
        ? "No pulls this week. Add comics on League of Comic Geeks."
        : "Nothing listed this week yet."
    } else {
      if (!showArchiveFallback())
        loadError = "Nothing listed here yet, or the site changed its layout."
    }
  }

  function finishHtml(verdict, body) {
    var parsed = Model.parseReleases(body)
    issues = parsed
    if (verdict.status === "ok") {
      if (weekOffset === 0) {
        lastSuccessfulMs = Date.now()
        saveCache(parsed)
      }
    } else if (verdict.status === "suspect") {
      loadError = "Nothing listed here yet, or the site changed its layout."
    } else {
      loadError = "Nothing found for this week."
    }
  }

  // When a live fetch fails while browsing history, fall back to the local
  // archive snapshot for that week, if one exists.
  function showArchiveFallback() {
    if (source !== "pulls" || weekOffset === 0) return false
    var snap = doc.archive[Model.weekKeyOf(browsedWeekTs())]
    if (!snap || !snap.issues || snap.issues.length === 0) return false
    issues = snap.issues
    viewingArchive = true
    loadError = "Live fetch failed - showing the archived snapshot."
    return true
  }

  // The stored cookie stopped working. Keep identity fields so Settings can
  // say who expired, clear the session, and continue anonymously.
  function expireSession() {
    commit(Store.setAccount(doc, { session: "" }))
    loginStatus = "Your session expired - sign in again in Settings. Showing public data meanwhile."
    startRefresh()
  }

  // Cache the last good fetch so restarts open instantly and offline reads
  // still show data. Gated by the local-storage toggle.
  function saveCache(parsed) {
    if (!storageEnabled) return
    var weekKey = ""
    for (var i = 0; i < parsed.length; i++)
      if (parsed[i].releaseTs) { weekKey = Model.weekKeyOf(parsed[i].releaseTs); break }
    var next = Store.normalizeDoc(doc)
    next.cache = { weekKey: weekKey, fetchedMs: Date.now(), issues: parsed }
    // Pull lists are only public while current: snapshot them now when
    // archiving is on, so history accumulates week by week.
    next = Store.archiveIssues(next, weekKey, parsed, { enabled: archiveEnabled && source === "pulls" && weekOffset === 0 })
    commit(Store.pruneArchive(next, 26))
  }

  // Load cached issues into the view at startup / before first refresh.
  function restoreFromCache() {
    if (issues.length > 0) return
    if (doc.cache.issues.length > 0 && Date.now() - doc.cache.fetchedMs < 7 * 86400000) {
      issues = doc.cache.issues
      lastSuccessfulMs = doc.cache.fetchedMs
    }
  }

  // -------------------------------------------------------- profile validation
  function requestProfileSave(name) {
    if (validatingProfile) return
    if (name === "") {
      // Blank means releases-only mode; valid by definition.
      profileValid = true
      profileStatus = "Cleared. Longbox will track general weekly releases."
      commit(Store.setProfile(doc, "", Date.now()))
      startRefresh()
      return
    }
    validatingProfile = true
    profileStatus = "Checking " + name + "..."
    validateProcess.profileUsername = name
    validateProcess.command = ["/usr/bin/env", "curl", "-sL", "--max-time", "20",
      "--max-filesize", String(Model.RESPONSE_BYTE_LIMIT),
      "-A", root.httpAgent].concat(curlArgs(),
      ["https://leagueofcomicgeeks.com/profile/" + encodeURIComponent(name)])
    console.warn("[longbox] validate: starting for", name)
    validateProcess.running = true
    validateWatchdog.restart()
  }

  // Safety net: if validation somehow never exits (spawn failure, hang),
  // release the button again instead of leaving the UI stuck on Checking.
  Timer {
    id: validateWatchdog
    interval: 30000
    repeat: false
    onTriggered: {
      if (!root.validatingProfile) return
      console.warn("[longbox] validate: watchdog fired, releasing UI")
      validateProcess.running = false
      root.validatingProfile = false
      root.profileValid = false
      root.profileStatus = "The check timed out. Try again in a moment."
    }
  }

  function finishProfileValidation(exitCode) {
    validateWatchdog.stop()
    validatingProfile = false
    // Byte cap tripped: the page is truncated mid-markup, so neither the
    // challenge nor the missing-profile verdicts below would be honest.
    if (Model.isSizeOverflow(exitCode)) {
      console.warn("[longbox] validate: response exceeded byte cap")
      profileValid = false
      profileStatus = "The profile check hit a response size limit. Try again."
      return
    }
    var body = validateStdout.text
    var name = validateProcess.profileUsername
    var verdict = Model.diagnose(body)
    var looksReal = exitCode === 0 &&
      verdict.status !== "challenge" &&
      body.indexOf("/profile/" + name.toLowerCase()) >= 0
    console.warn("[longbox] validate: finished verdict=", verdict.status,
      "looksReal=", looksReal)

    if (looksReal) {
      profileValid = true
      profileStatus = name + "'s pull list found and saved."
      commit(Store.setProfile(doc, name, Date.now()))
      if (activeTab === "settings" && source === "pulls") activeTab = "comics"
      startRefresh()
    } else if (verdict.status === "challenge") {
      profileValid = false
      profileStatus = "The site bot-checked us. Open leagueofcomicgeeks.com in your browser once, then try Save again. If it keeps failing, add a clearance cookie in Settings."
    } else {
      profileValid = false
      profileStatus = "Could not find that profile. Check the spelling on leagueofcomicgeeks.com."
    }
  }

  // ------------------------------------------------------------- opt-in sign-in
  // POSTs credentials once, keeps only the returned ci_session cookie, then
  // discovers the numeric user id with one authenticated pull-list request
  // sent without user_id (the server resolves the session owner).
  function requestSignIn(name, pass) {
    if (signingIn || name === "" || pass === "") return
    signingIn = true
    loginStatus = "Signing in as " + name + "..."
    pendingName = name
    // Credentials travel via environment, never argv: process command lines
    // are world-readable, environ is not.
    loginProcess.environment = ({
      LONGBOX_USER: name,
      LONGBOX_PASS: pass,
      LONGBOX_AGENT: root.httpAgent,
      LONGBOX_COOKIES: cookieArgs("").join(" ")
    })
    loginProcess.command = ["/bin/sh", "-c",
      "exec curl -siL --max-time 25 --max-filesize " + Model.RESPONSE_BYTE_LIMIT +
      " -A \"$LONGBOX_AGENT\" $LONGBOX_COOKIES" +
      " --data-urlencode \"username=$LONGBOX_USER\"" +
      " --data-urlencode \"password=$LONGBOX_PASS\"" +
      " \"https://leagueofcomicgeeks.com/login\"",
      "longbox-login"]
    loginProcess.running = true
    loginWatchdog.restart()
  }

  function finishSignIn(username, exitCode) {
    loginWatchdog.stop()
    signingIn = false
    // Byte cap tripped: the header/body dump is truncated - no reliable
    // Set-Cookie can be mined from it.
    if (Model.isSizeOverflow(exitCode)) {
      loginStatus = "Sign-in failed - the site returned an oversized response. Try again shortly."
      return
    }
    var out = loginStdout.text
    var session = Model.extractCiSession(out)
    var errText = Model.loginErrorFromHtml(out)

    if (errText !== "") {
      loginStatus = "Sign-in failed: " + errText
      return
    }
    if (session === "") {
      loginStatus = "Could not sign in - network trouble or a bot check. Try again shortly."
      return
    }

    pendingSession = session
    signingIn = true
    // Learn the numeric account id from the public profile page - reliable,
    // unlike the API's user echo which follows request params, not sessions.
    whoamiProcess.command = ["/usr/bin/env", "curl", "-sL", "--max-time", "20",
      "-A", root.httpAgent].concat(cookieArgs(session),
      ["https://leagueofcomicgeeks.com/profile/" + encodeURIComponent(username) + "/pull-list"])
    whoamiProcess.running = true
    whoamiWatchdog.restart()
    loginStatus = "Signed in as " + username + ", loading your lists..."
  }

  function finishWhoami(exitCode) {
    whoamiWatchdog.stop()
    signingIn = false
    // Byte cap tripped: the profile page is truncated - the user id may be
    // missing or mangled, so refuse the sign-in commit.
    if (Model.isSizeOverflow(exitCode)) {
      loginStatus = "Could not confirm the session - the profile page came back oversized. Try again."
      return
    }
    var uid = Model.extractProfileUserId(whoamiStdout.text)
    if (uid <= 0) {
      loginStatus = "Could not find a profile for that name. Check the spelling and try again."
      return
    }
    commit(Store.setAccount(doc, {
      session: pendingSession,
      userId: uid,
      name: pendingName,
      signedInAt: Date.now()
    }))
    ensureStatePerms()
    loginStatus = "Signed in as " + pendingName + ". Past weeks now load live."
    if (activeTab === "settings" && source === "pulls") activeTab = "comics"
    startRefresh()
  }

  function signOut() {
    commit(Store.clearAccount(doc))
    loginStatus = "Signed out. Pull lists now follow the public profile above."
    if (weekOffset !== 0) backToCurrentWeek()
    else startRefresh()
  }

  // The state doc holds a bearer cookie; keep the file owner-only. Atomic
  // writes recreate the inode, so re-assert after each commit.
  Process {
    id: permsProcess
    running: false
  }

  function ensureStatePerms() {
    if (permsProcess.running) return
    permsProcess.command = ["/usr/bin/chmod", "600",
      Quickshell.env("HOME") + "/.local/state/omarchy/settings/longbox.json"]
    permsProcess.running = true
  }

  Process {
    id: loginProcess
    running: false

    environment: ({})

    stdout: StdioCollector {
      id: loginStdout
      waitForEnd: true
    }

    onExited: function(exitCode) {
      Qt.callLater(function() { root.finishSignIn(root.pendingName, exitCode) })
    }
  }

  Timer {
    id: loginWatchdog
    interval: 30000
    repeat: false
    onTriggered: {
      if (!root.signingIn) return
      loginProcess.running = false
      root.signingIn = false
      root.loginStatus = "Sign-in timed out. Try again in a moment."
    }
  }

  Process {
    id: whoamiProcess
    running: false

    stdout: StdioCollector {
      id: whoamiStdout
      waitForEnd: true
    }

    onExited: function(exitCode) {
      Qt.callLater(function() { root.finishWhoami(exitCode) })
    }
  }

  Timer {
    id: whoamiWatchdog
    interval: 30000
    repeat: false
    onTriggered: {
      if (!root.signingIn) return
      whoamiProcess.running = false
      root.signingIn = false
      root.loginStatus = "Could not confirm the session. Try again in a moment."
    }
  }

  function openIssue(index) {
    var issue = visibleIssues[index]
    if (issue) Qt.openUrlExternally(issue.url)
  }

  // ------------------------------------------------------------- rich tooltips
  // One shared popup; delegates request show/hide with themselves as the
  // source so moving between rows never flickers. The Popup parents to the
  // key catcher, painting above the Flickable's clip.
  property var tipSource: null

  function showComicTip(issue, srcItem) {
    if (!comicTip || issue === null) return
    tipSource = srcItem
    comicTip.issue = issue
    comicTip.open()
    positionComicTip(srcItem)
  }

  function hideComicTip(srcItem) {
    if (tipSource !== srcItem) return
    tipSource = null
    comicTip.close()
  }

  function positionComicTip(srcItem) {
    if (!srcItem || !comicTip.opened) return
    var p = srcItem.mapToItem(keyCatcher, 0, 0)
    var w = comicTip.implicitWidth || Style.space(300)
    var h = comicTip.implicitHeight || Style.space(100)
    comicTip.x = Math.max(Style.space(4),
      Math.min(p.x + srcItem.width / 2 - w / 2, keyCatcher.width - w - Style.space(4)))
    comicTip.y = p.y - h - Style.space(6)
    if (comicTip.y < Style.space(4))
      comicTip.y = Math.min(p.y + srcItem.height + Style.space(6), keyCatcher.height - h - Style.space(4))
  }

  // Flip one local mark facet for an issue: "collected", "read" (stored as
  // readAt timestamp), or "wishlist". Persists immediately; marks survive
  // even with comic-data caching disabled.
  function toggleMark(id, facet) {
    var entry = doc.marks[id] || {}
    var key = facet === "read" ? "readAt" : facet
    var patch = {}
    patch[key] = !entry[key]
    commit(Store.markIssue(doc, id, patch))
  }

  // ---------------------------------------------------------- week navigation
  // Releases browse any week live via dated URLs. Pull lists are only public
  // while current, so past weeks render from the local archive snapshot.
  property bool viewingArchive: false

  function browsedWeekTs() {
    var anchor = cachedAnchorMs()
    return anchor ? Model.shiftWeekTs(anchor, weekOffset) : 0
  }

  function goWeek(delta) {
    setWeekOffset(weekOffset + delta)
  }

  function backToCurrentWeek() {
    setWeekOffset(0)
  }

  function setWeekOffset(offset) {
    var clamped = Math.max(-52, Math.min(2, offset))
    if (clamped === weekOffset && issues.length > 0 && !loadError) return
    weekOffset = clamped
    query = ""
    loadWeek()
  }

  function loadWeek() {
    viewingArchive = false
    if (weekOffset === 0 || cachedAnchorMs() === 0) {
      startRefresh()
      return
    }
    // Anonymous pulls are only public while current: past weeks render from
    // the local archive snapshot. Signed in, the API serves any week live.
    if (source === "pulls" && !signedIn) {
      var snap = doc.archive[Model.weekKeyOf(browsedWeekTs())]
      if (snap) {
        issues = snap.issues
        loadError = ""
        viewingArchive = true
      } else {
        issues = []
        loadError = "This week is not archived yet. Weeks are saved while they are current when archiving is on - or sign in to browse history live."
      }
      return
    }
    startRefresh()
  }

  onOpenedChanged: {
    if (opened) {
      query = ""
      hideCollected = false
      hideRead = false
      wishlistOnly = false
      if (needsSetup) activeTab = "settings"
      restoreFromCache()
      if (lastSuccessfulMs === 0 || Date.now() - lastSuccessfulMs >= refreshIntervalMs)
        startRefresh()
    } else {
      tipSource = null
      comicTip.close()
    }
  }

  Timer {
    interval: root.refreshIntervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.startRefresh()
  }

  // Single delayed retry after a bot-checked response.
  Timer {
    id: retryTimer
    interval: 6000
    repeat: false
    onTriggered: root.startRefresh(true)
  }

  Process {
    id: fetchProcess
    running: false

    stdout: StdioCollector {
      id: fetchStdout
      waitForEnd: true
    }

    onExited: function(exitCode) {
      root.fetchExitCode = exitCode
      Qt.callLater(root.finishRefresh)
    }
  }

  Process {
    id: validateProcess
    running: false
    property string profileUsername: ""

    stdout: StdioCollector {
      id: validateStdout
      waitForEnd: true
    }

    onExited: function(exitCode) {
      console.warn("[longbox] validate: exited code=", exitCode,
        "bytes=", validateStdout.text ? validateStdout.text.length : 0)
      Qt.callLater(function() { root.finishProfileValidation(exitCode) })
    }
  }

  Component.onCompleted: {
    if (needsSetup) activeTab = "settings"
    ensureStatePerms()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        onContentYChanged: comicTip.close()
        onMovingChanged: if (moving) comicTip.close()

        Column {
          id: content
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: root.needsSetup ? "Longbox" : (root.source === "pulls"
              ? root.displayUser + "'s pulls" : "New comics")
            meta: root.loading ? "Loading..." : root.weekLabel + " · "
              + root.visibleIssues.length + (root.visibleIssues.length === 1 ? " issue" : " issues")
              + (root.viewingArchive ? " · archived" : "")
            detail: root.loadError
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

            iconComponent: Component {
              Text {
                text: "\uf02d"
                color: root.loadError !== "" ? Color.urgent : root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.display
              }
            }

            trailingControl: Component {
              Row {
                spacing: Style.space(4)

                PanelActionButton {
                  iconText: "\uf021"
                  tooltipText: "Refresh"
                  foreground: root.barForeground
                  fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                  enabled: !root.loading
                  onClicked: root.startRefresh()
                }
              }
            }
          }

          ButtonGroup {
            width: parent.width
            options: [
              { value: "comics", label: "Comics" },
              { value: "settings", label: "Settings" }
            ]
            value: root.activeTab
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            focusable: false
            onChanged: function(v) { root.activeTab = v }
          }

          Row {
            width: parent.width
            spacing: Style.space(6)
            visible: root.activeTab === "comics" && !root.needsSetup

            PanelActionButton {
              id: prevWeekButton
              anchors.verticalCenter: parent.verticalCenter
              iconText: "\uf060"
              tooltipText: "Previous week"
              foreground: root.barForeground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              enabled: !root.loading && root.cachedAnchorMs() !== 0 && root.weekOffset > -52
              onClicked: root.goWeek(-1)
            }

            PanelActionButton {
              id: nextWeekButton
              anchors.verticalCenter: parent.verticalCenter
              iconText: "\uf061"
              tooltipText: "Next week"
              foreground: root.barForeground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              enabled: !root.loading && root.cachedAnchorMs() !== 0 && root.weekOffset < 2
              onClicked: root.goWeek(1)
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - prevWeekButton.width - nextWeekButton.width
                - (root.weekOffset !== 0 ? todayButton.width : 0)
                - parent.spacing * 2
              text: {
                var label = Model.weekLabel(root.browsedWeekTs())
                if (label === "") label = "This week"
                if (root.source === "pulls" && root.weekOffset !== 0) label += " (from archive)"
                return label
              }
              color: Qt.darker(root.barForeground, 1.3)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            PanelActionButton {
              id: todayButton
              anchors.verticalCenter: parent.verticalCenter
              visible: root.weekOffset !== 0
              iconText: "\uf017"
              tooltipText: "Back to the current week"
              foreground: root.barForeground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              enabled: !root.loading
              onClicked: root.backToCurrentWeek()
            }
          }

          SettingsTab {
            width: parent.width
            visible: root.activeTab === "settings"
            panel: root
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

            onProfileSaveRequested: function(name) { root.requestProfileSave(name) }
            onSettingChanged: function(key, value) { root.changeSetting(key, value) }
            onClearComicDataRequested: root.clearAllComicData()
            onClearArchiveRequested: root.clearArchiveOnly()
            onSignInRequested: function(name, pass) { root.requestSignIn(name, pass) }
            onSignOutRequested: root.signOut()
            onConnectionChanged: function(clearance, ua) {
              root.commit(Store.setConnection(root.doc, clearance, ua))
            }
            onOpenSiteRequested: Qt.openUrlExternally("https://leagueofcomicgeeks.com")
          }

          Column {
            id: comicsList
            width: parent.width
            spacing: Style.space(0)
            visible: root.activeTab === "comics"

              TextField {
                visible: root.source === "releases"
                width: parent.width
                placeholderText: "Filter titles or publishers..."
                color: root.barForeground
                placeholderTextColor: Qt.darker(root.barForeground, 1.6)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
                background: Rectangle {
                  color: Qt.darker(root.barForeground, 8)
                  opacity: 0.35
                  radius: Style.space(6)
                }
                onTextChanged: root.query = text
              }

              Row {
                width: parent.width
                spacing: Style.space(6)
                visible: root.visibleIssues.length > 0 || root.hideCollected || root.hideRead || root.wishlistOnly

                Button {
                  text: "Hide collected"
                  bordered: true
                  selected: root.hideCollected
                  foreground: root.barForeground
                  fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                  onClicked: root.hideCollected = !root.hideCollected
                }

                Button {
                  text: "Hide read"
                  bordered: true
                  selected: root.hideRead
                  foreground: root.barForeground
                  fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                  onClicked: root.hideRead = !root.hideRead
                }

                Button {
                  text: "Wishlist only"
                  bordered: true
                  selected: root.wishlistOnly
                  foreground: root.barForeground
                  fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                  onClicked: root.wishlistOnly = !root.wishlistOnly
                }
              }

              // NOTE: a Repeater's delegates are siblings inside this
              // Column, not children of the Repeater, so hiding the
              // Repeater hides nothing. Each row carries the visibility
              // binding itself; the positioner then skips them.
              Repeater {
                id: listRepeat
                model: root.visibleIssues

                delegate: ItemDelegate {
                  id: issueRow
                  required property var modelData
                  required property int index

                  readonly property var mark: root.doc.marks[modelData.id] || null
                  readonly property bool isCollected: mark ? !!mark.collected : false
                  readonly property bool isRead: mark ? !!mark.readAt : false
                  readonly property bool isWished: mark ? !!mark.wishlist : false

                  visible: root.isListView
                  width: comicsList.width
                  height: Math.max(Style.space(58), coverSlot.height + Style.space(8))
                  background: null
                  hoverEnabled: true

                  onClicked: root.openIssue(index)
                  onHoveredChanged: {
                    if (hovered) root.showComicTip(modelData, issueRow)
                    else root.hideComicTip(issueRow)
                  }

                  Row {
                    anchors.fill: parent
                    spacing: Style.space(10)

                    Item {
                      id: coverSlot
                      visible: root.showCovers
                      width: visible ? Style.space(38) : 0
                      height: visible ? Style.space(56) : 0
                      anchors.verticalCenter: parent.verticalCenter

                      Image {
                        id: coverImage
                        anchors.fill: parent
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        source: issueRow.modelData.cover !== "" ? issueRow.modelData.cover : ""
                      }

                      Text {
                        visible: issueRow.isCollected
                        text: "\uf00c"
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        color: Color.accent
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.space(10)
                      }

                      Text {
                        visible: issueRow.isWished
                        text: "\uf005"
                        anchors.right: parent.right
                        anchors.top: parent.top
                        color: Color.accent
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.space(10)
                      }
                    }

                    Column {
                      id: textColumn
                      width: parent.width - coverSlot.width - badgeText.width - actionsStrip.width
                        - parent.spacing * 3
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(2)

                      Text {
                        width: parent.width
                        text: Model.cleanText(issueRow.modelData.title)
                        color: issueRow.isRead ? Qt.darker(root.barForeground, 2.1) : root.barForeground
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.body
                        font.strikeout: issueRow.isRead
                        elide: Text.ElideRight
                      }

                      Text {
                        width: parent.width
                        text: {
                          var parts = []
                          if (issueRow.modelData.publisher !== "") parts.push(Model.cleanText(issueRow.modelData.publisher))
                          if (issueRow.modelData.price !== "") parts.push(issueRow.modelData.price)
                          if (root.source === "releases" && issueRow.modelData.pulls > 0)
                            parts.push(Model.formatPulls(issueRow.modelData.pulls) + " pulls")
                          return parts.join("  ·  ")
                        }
                        color: Qt.darker(root.barForeground, 1.45)
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }

                    Text {
                      id: badgeText
                      anchors.verticalCenter: parent.verticalCenter
                      text: {
                        var days = Model.daysUntil(issueRow.modelData.releaseTs)
                        if (days === null) return ""
                        if (days <= 0) return "OUT"
                        return "in " + days + "d"
                      }
                      color: {
                        var days = Model.daysUntil(issueRow.modelData.releaseTs)
                        return days !== null && days <= 0 ? Color.accent : Qt.darker(root.barForeground, 1.3)
                      }
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }

                    Row {
                      id: actionsStrip
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(6)
                      opacity: issueRow.hovered ? 1 : 0

                      MarkGlyph {
                        anchors.verticalCenter: parent.verticalCenter
                        activeMark: issueRow.isCollected
                        text: "\uf00c"
                        onActivated: root.toggleMark(issueRow.modelData.id, "collected")
                      }

                      MarkGlyph {
                        anchors.verticalCenter: parent.verticalCenter
                        activeMark: issueRow.isRead
                        text: "\uf06e"
                        onActivated: root.toggleMark(issueRow.modelData.id, "read")
                      }

                      MarkGlyph {
                        anchors.verticalCenter: parent.verticalCenter
                        activeMark: issueRow.isWished
                        text: "\uf005"
                        onActivated: root.toggleMark(issueRow.modelData.id, "wishlist")
                      }
                    }
                  }
                }
              }

              IssueGrid {
                visible: !root.isListView
                width: parent.width
                height: contentHeight
                panel: root
                model: root.visibleIssues
                foreground: root.barForeground
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                onIssueActivated: function(index) { root.openIssue(index) }
              }

              Text {
                id: emptyState
                width: parent.width
                visible: !root.loading && root.visibleIssues.length === 0
                text: root.needsSetup
                  ? "Set your League of Comic Geeks username in Settings to track your pull list."
                  : (root.loadError !== "" ? root.loadError :
                    (root.source === "pulls"
                      ? "No pulls this week, or the list is private. Add comics on League of Comic Geeks."
                      : "No matching releases."))
                color: Qt.darker(root.barForeground, 1.45)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
          }
        }
      }

      ComicToolTip {
        id: comicTip
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
      }
    }
  }
}
