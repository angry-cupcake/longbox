import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "hari.comics"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  // Settings (persisted in shell.json by the shell)
  readonly property string username: String(setting("username", "cupcakeisangry") || "").trim()
  readonly property string source: setting("source", "pulls") === "releases" ? "releases" : "pulls"
  readonly property bool excludeVariants: setting("excludeVariants", true) !== false
  readonly property bool showCovers: setting("showCovers", true) !== false
  readonly property int refreshIntervalMs: Math.max(10, Number(setting("refreshIntervalMin", 60)) || 60) * 60000

  // State
  property var issues: []
  property string query: ""
  property bool loading: false
  property string loadError: ""
  property double lastSuccessfulMs: 0

  readonly property var visibleIssues: Model.filterIssues(issues, {
    excludeVariants: excludeVariants,
    query: query
  })
  readonly property string barCount: visibleIssues.length > 0 ? String(visibleIssues.length) : ""

  function pageUrl() {
    return Model.feedUrl(username, source)
  }

  readonly property string weekLabel: {
    for (var i = 0; i < issues.length; i++)
      if (!issues[i].isVariant && issues[i].releaseTs) return Model.weekLabel(issues[i].releaseTs)
    return ""
  }

  function barTooltipText() {
    var who = source === "pulls" && username !== "" ? username + "'s pull list" : "New comics this week"
    if (weekLabel !== "") who += " \u00b7 " + weekLabel
    if (loadError !== "") return who + " (offline)"
    return who
  }
  readonly property string barTooltip: barTooltipText()

  function startRefresh() {
    if (fetchProcess.running) return
    loading = true
    loadError = ""
    fetchProcess.command = ["/usr/bin/env", "curl", "-sL", "--max-time", "25",
      "-A", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
      pageUrl()]
    fetchProcess.running = true
  }

  function finishRefresh() {
    loading = false
    var body = fetchStdout.text
    var parsed = Model.parseReleases(body)
    if (parsed.length > 0 || fetchExitCode === 0) {
      issues = parsed
      if (parsed.length > 0) lastSuccessfulMs = Date.now()
      else loadError = "Nothing found for this week."
    } else {
      loadError = "Could not reach League of Comic Geeks."
    }
  }

  function openIssue(index) {
    var issue = visibleIssues[index]
    if (issue) Qt.openUrlExternally(issue.url)
  }

  onOpenedChanged: {
    if (opened) {
      query = ""
      if (lastSuccessfulMs === 0 || Date.now() - lastSuccessfulMs >= refreshIntervalMs)
        startRefresh()
    }
  }

  Timer {
    interval: root.refreshIntervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.startRefresh()
    }
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
  property int fetchExitCode: 0

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

        Column {
          id: content
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: root.source === "pulls" && root.username !== ""
              ? root.username + "'s pulls" : "New comics"
            meta: root.loading ? "Loading\u2026" : root.weekLabel + " \u00b7 "
              + root.visibleIssues.length + (root.visibleIssues.length === 1 ? " issue" : " issues")
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

          TextField {
            visible: root.source === "releases"
            width: parent.width
            placeholderText: "Filter titles or publishers\u2026"
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

          Repeater {
            model: root.visibleIssues

            delegate: ItemDelegate {
              required property var modelData
              required property int index
              width: content.width
              height: Math.max(Style.space(58), coverImage.height + Style.space(8))
              background: null

              onClicked: root.openIssue(index)

              Row {
                anchors.fill: parent
                spacing: Style.space(10)

                Image {
                  id: coverImage
                  visible: root.showCovers
                  width: Style.space(38)
                  height: visible ? Style.space(56) : 0
                  anchors.verticalCenter: parent.verticalCenter
                  asynchronous: true
                  fillMode: Image.PreserveAspectCrop
                  source: modelData.cover !== "" ? modelData.cover : ""
                }

                Column {
                  width: parent.width - (coverImage.visible ? coverImage.width : 0) - Style.space(10) - badge.width
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Text {
                    width: parent.width
                    text: Model.cleanText(modelData.title)
                    color: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    text: {
                      var parts = []
                      if (modelData.publisher !== "") parts.push(Model.cleanText(modelData.publisher))
                      if (modelData.price !== "") parts.push(modelData.price)
                      if (root.source === "releases" && modelData.pulls > 0)
                        parts.push(Model.formatPulls(modelData.pulls) + " pulls")
                      return parts.join("  \u00b7  ")
                    }
                    color: Qt.darker(root.barForeground, 1.45)
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Text {
                  id: badge
                  anchors.verticalCenter: parent.verticalCenter
                  text: {
                    var days = Model.daysUntil(modelData.releaseTs)
                    if (days === null) return ""
                    if (days <= 0) return "OUT"
                    return "in " + days + "d"
                  }
                  color: {
                    var days = Model.daysUntil(modelData.releaseTs)
                    return days !== null && days <= 0 ? Color.accent : Qt.darker(root.barForeground, 1.3)
                  }
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: !root.loading && root.visibleIssues.length === 0
            text: root.source === "pulls"
              ? "No pulls this week, or the list is private. Add comics on League of Comic Geeks."
              : "No matching releases."
            color: Qt.darker(root.barForeground, 1.45)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
