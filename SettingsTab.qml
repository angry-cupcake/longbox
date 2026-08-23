import QtQuick
import qs.Commons
import qs.Ui

// Settings tab: profile setup, preferences, and storage management.
// Stateless about persistence: every change goes out through signals and
// the owning Panel commits it to the state document.
Column {
  id: root

  property var panel: null
  property color foreground: panel ? panel.barForeground : Color.foreground
  property string fontFamily: panel && panel.bar ? panel.bar.fontFamily : Style.font.family

  signal profileSaveRequested(string username)
  signal settingChanged(string key, var value)
  signal clearComicDataRequested()
  signal clearArchiveRequested()
  signal connectionChanged(string clearance, string userAgent)
  signal openSiteRequested()

  spacing: Style.space(12)

  Component.onCompleted: {
    if (panel) {
      clearanceField.text = panel.doc.connection.clearance
      uaField.text = panel.doc.connection.userAgent
    }
  }

  // ------------------------------------------------------------------ profile
  PanelSectionHeader {
    width: parent.width
    text: "Profile"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Text {
    width: parent.width
    text: "Enter your League of Comic Geeks username. Pull lists are public, so no login is needed. Leave blank to track general weekly releases instead."
    color: Qt.darker(root.foreground, 1.45)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Item {
    id: profileRow
    width: parent.width
    height: Math.max(nameField.implicitHeight, saveButton.implicitHeight)

    TextField {
      id: nameField
      anchors.left: parent.left
      anchors.right: saveButton.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      placeholderText: "username"
      color: root.foreground
      font.family: root.fontFamily
      onAccepted: root.profileSaveRequested(text.trim())
    }

    Button {
      id: saveButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: panel && panel.validatingProfile ? "\uf252" : "Save"
      bordered: true
      enabled: !panel || !panel.validatingProfile
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.profileSaveRequested(nameField.text.trim())
    }
  }

  Text {
    width: parent.width
    visible: panel ? panel.profileStatus !== "" : false
    text: panel ? panel.profileStatus : ""
    color: {
      if (!panel) return Qt.darker(root.foreground, 1.45)
      return panel.profileValid === true ? Color.accent : Color.urgent
    }
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  PanelSeparator { width: parent.width }

  // -------------------------------------------------------------- preferences
  PanelSectionHeader {
    width: parent.width
    text: "Preferences"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  LabeledRow {
    width: parent.width
    label: "Source"
    detail: "Pull list tracks your subscriptions. Releases lists everything shipping."
    foreground: root.foreground
    fontFamily: root.fontFamily

    ButtonGroup {
      options: [
        { value: "pulls", label: "Pulls" },
        { value: "releases", label: "Releases" }
      ]
      value: panel ? panel.source : "pulls"
      foreground: root.foreground
      fontFamily: root.fontFamily
      focusable: false
      onChanged: function(v) { root.settingChanged("source", v) }
    }
  }

  LabeledRow {
    width: parent.width
    label: "View"
    detail: "Grid view shows larger cover art."
    foreground: root.foreground
    fontFamily: root.fontFamily

    ButtonGroup {
      options: [
        { value: "list", label: "List" },
        { value: "grid", label: "Grid" }
      ]
      value: panel ? String(panel.doc.settings.viewMode) : "list"
      foreground: root.foreground
      fontFamily: root.fontFamily
      focusable: false
      onChanged: function(v) { root.settingChanged("viewMode", v) }
    }
  }

  Toggle {
    width: parent.width
    label: "Hide variant covers"
    description: "Applies to the releases source."
    checked: panel ? panel.excludeVariants : true
    foreground: root.foreground
    accent: Color.accent
    fontFamily: root.fontFamily
    onClicked: root.settingChanged("excludeVariants", !(panel && panel.excludeVariants))
  }

  Toggle {
    width: parent.width
    label: "Show cover art"
    description: "Cover thumbnails in comic lists."
    checked: panel ? panel.showCovers : true
    foreground: root.foreground
    accent: Color.accent
    fontFamily: root.fontFamily
    onClicked: root.settingChanged("showCovers", !(panel && panel.showCovers))
  }

  LabeledRow {
    width: parent.width
    label: "Refresh interval"
    detail: "How often to re-fetch. LoCG rate-limits aggressive clients."
    foreground: root.foreground
    fontFamily: root.fontFamily

    ButtonGroup {
      options: [
        { value: "30", label: "30m" },
        { value: "60", label: "1h" },
        { value: "120", label: "2h" },
        { value: "360", label: "6h" },
        { value: "720", label: "12h" }
      ]
      value: panel ? String(panel.refreshIntervalMs / 60000) : "60"
      foreground: root.foreground
      fontFamily: root.fontFamily
      focusable: false
      onChanged: function(v) { root.settingChanged("refreshIntervalMin", parseInt(v, 10)) }
    }
  }

  PanelSeparator { width: parent.width }

  // ------------------------------------------------------------------ storage
  PanelSectionHeader {
    width: parent.width
    text: "Storage"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Toggle {
    width: parent.width
    label: "Store comic data locally"
    description: panel && panel.doc.settings.storeDataLocally
      ? "Keeps a small cache so the panel opens instantly and works offline."
      : "Off: nothing fetched is saved. Data re-fetches after every restart and the panel will not open offline."
    checked: panel ? panel.doc.settings.storeDataLocally : true
    foreground: root.foreground
    accent: Color.accent
    fontFamily: root.fontFamily
    onClicked: {
      var next = !(panel && panel.doc.settings.storeDataLocally)
      if (!next) root.clearComicDataRequested()
      root.settingChanged("storeDataLocally", next)
    }
  }

  Toggle {
    width: parent.width
    label: "Archive past pull lists"
    description: {
      if (!(panel && panel.doc.settings.storeDataLocally))
        return "Requires local storage."
      if (!(panel && panel.doc.settings.archivePulls))
        return "Off: previous weeks are unavailable. On: each week's pulls are snapshotted while current, building history over time."
      return "Archived weeks: " + (panel ? panel.archivedWeekCount : 0)
    }
    checked: panel ? panel.doc.settings.archivePulls : false
    foreground: root.foreground
    accent: Color.accent
    fontFamily: root.fontFamily
    onClicked: root.settingChanged("archivePulls", !(panel && panel.doc.settings.archivePulls))
  }

  Row {
    width: parent.width
    spacing: Style.space(8)

    Button {
      text: "Clear cache"
      bordered: true
      enabled: panel ? panel.doc.cache.fetchedMs > 0 : false
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.clearComicDataRequested()
    }

    Button {
      text: "Clear archive"
      bordered: true
      enabled: panel ? panel.archivedWeekCount > 0 : false
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.clearArchiveRequested()
    }
  }

  Text {
    width: parent.width
    text: "Your marks (collected, read, wishlist) are always stored locally on this device. Nothing is ever sent anywhere except League of Comic Geeks page requests."
    color: Qt.darker(root.foreground, 1.45)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  PanelSeparator { width: parent.width }

  // ---------------------------------------------------------------- connection
  PanelSectionHeader {
    width: parent.width
    text: "Connection"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Text {
    width: parent.width
    text: panel && panel.doc.connection.clearance !== ""
      ? "Clearance cookie active."
      : "If the site keeps bot-checking the widget: open leagueofcomicgeeks.com in your browser, solve any check, then copy the cf_clearance cookie (browser devtools, Application tab, Cookies) into this field along with your browser's exact User-Agent string. Both must come from the same browser session."
    color: Qt.darker(root.foreground, 1.45)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  TextField {
    id: clearanceField
    width: parent.width
    placeholderText: "cf_clearance cookie value"
    password: true
    color: root.foreground
    font.family: root.fontFamily
    onEditingFinished: root.connectionChanged(clearanceField.text, uaField.text)
  }

  TextField {
    id: uaField
    width: parent.width
    placeholderText: "Your browser's User-Agent string"
    color: root.foreground
    font.family: root.fontFamily
    onEditingFinished: root.connectionChanged(clearanceField.text, uaField.text)
  }

  Row {
    spacing: Style.space(8)

    Button {
      text: "Open League of Comic Geeks"
      bordered: true
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.openSiteRequested()
    }

    Button {
      text: "Clear clearance"
      bordered: true
      enabled: panel ? panel.doc.connection.clearance !== "" : false
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.connectionChanged("", "")
    }
  }

  // Simple label-left, control-right row used across sections.
  component LabeledRow: Column {
    property string label: ""
    property string detail: ""
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family

    spacing: Style.space(3)

    Text {
      text: parent.label
      color: parent.foreground
      font.family: parent.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }

    Text {
      text: parent.detail
      color: Qt.darker(parent.foreground, 1.5)
      font.family: parent.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      width: parent.width
    }
  }
}
