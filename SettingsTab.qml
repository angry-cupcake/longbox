import QtQuick
import qs.Commons
import qs.Ui

// Settings tab, grouped into collapsible sections ordered by how often the
// options are used. Stateless about persistence: every change goes out
// through signals and the owning Panel commits it to the state document.
// Section expansion is session-only UI state.
Column {
  id: root

  property var panel: null
  property color foreground: panel ? panel.barForeground : Color.foreground
  property string fontFamily: panel && panel.bar ? panel.bar.fontFamily : Style.font.family

  signal profileSaveRequested(string username)
  signal settingChanged(string key, var value)
  signal clearComicDataRequested()
  signal clearArchiveRequested()
  signal signInRequested(string username, string password)
  signal signOutRequested()
  signal connectionChanged(string clearance, string userAgent)
  signal openSiteRequested()

  spacing: Style.space(12)

  Component.onCompleted: {
    if (panel) {
      clearanceField.text = panel.doc.connection.clearance
      uaField.text = panel.doc.connection.userAgent
    }
  }

  // A section with a tappable header and collapsible body. Content is
  // assigned via the default property.
  component Section: Column {
    id: sec
    required property string title
    property bool expanded: false
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family
    default property alias content: body.children
    width: parent ? parent.width : 0
    spacing: Style.space(10)

    Item {
      width: parent.width
      height: Math.max(headerText.implicitHeight, chevron.implicitHeight)

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: sec.expanded = !sec.expanded
      }

      Text {
        id: chevron
        anchors.verticalCenter: parent.verticalCenter
        text: sec.expanded ? "\uf0d7" : "\uf0da"
        color: Qt.darker(sec.foreground, 1.3)
        font.family: sec.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        id: headerText
        anchors.left: chevron.right
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        text: sec.title
        color: sec.foreground
        font.family: sec.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
    }

    Column {
      id: body
      visible: sec.expanded
      width: parent.width
      spacing: Style.space(12)
    }
  }

  // Label + detail on the left, control on the right, vertically centered.
  component SettingRow: Item {
    id: srow
    property string label: ""
    property string detail: ""
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family
    default property alias control: controlHost.data
    width: parent ? parent.width : 0
    height: Math.max(labelCol.height, controlHost.childrenRect.height)

    Column {
      id: labelCol
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - controlHost.childrenRect.width - Style.space(16)
      spacing: Style.space(2)

      Text {
        text: srow.label
        color: srow.foreground
        font.family: srow.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        visible: srow.label !== ""
      }

      Text {
        text: srow.detail
        color: Qt.darker(srow.foreground, 1.5)
        font.family: srow.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        width: parent.width
        visible: srow.detail !== ""
      }
    }

    Item {
      id: controlHost
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      implicitWidth: childrenRect.width
      implicitHeight: childrenRect.height
      width: implicitWidth
      height: implicitHeight
    }
  }

  // --------------------------------------------------------------- comics
  Section {
    title: "Comics"
    expanded: true
    width: parent.width
    foreground: root.foreground
    fontFamily: root.fontFamily

    SettingRow {
      width: parent.width
      label: "Source"
      detail: "Pull list tracks your subscriptions; releases lists everything shipping."
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

    SettingRow {
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

    SettingRow {
      width: parent.width
      label: "Refresh interval"
      detail: "How often to re-fetch. LoCG rate-limits aggressive clients."
      foreground: root.foreground
      fontFamily: root.fontFamily

      ButtonGroup {
        options: [
          { value: "60", label: "1h" },
          { value: "180", label: "3h" },
          { value: "360", label: "6h" },
          { value: "720", label: "12h" }
        ]
        value: panel ? String(panel.refreshIntervalMs / 60000) : "360"
        foreground: root.foreground
        fontFamily: root.fontFamily
        focusable: false
        onChanged: function(v) { root.settingChanged("refreshIntervalMin", parseInt(v, 10)) }
      }
    }
  }

  PanelSeparator { width: parent.width }

  // ------------------------------------------------------- league identity
  Section {
    id: leagueSection
    title: "League of Comic Geeks"
    width: parent.width
    foreground: root.foreground
    fontFamily: root.fontFamily
    expanded: panel ? (panel.needsSetup || panel.signedIn || panel.signingIn ||
                       panel.profileStatus !== "" || panel.loginStatus !== "") : false

    Text {
      width: parent.width
      text: {
        if (panel && panel.signedIn)
          return "Signed in, so your account's pull list is used and the profile below is only a fallback."
        return "Anonymous works fine: a profile name tracks its public pull list, or leave it blank for general weekly releases."
      }
      color: Qt.darker(root.foreground, 1.45)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    // ---- profile
    Text {
      width: parent.width
      text: "Profile"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
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

    // ---- account
    Text {
      width: parent.width
      text: "Account"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    Column {
      width: parent.width
      spacing: Style.space(8)
      visible: panel ? panel.signedIn : false

      Text {
        width: parent.width
        text: "Signed in as " + (panel ? panel.doc.account.name : "") + ". Pull lists load live for every week, past and future."
        color: Qt.darker(root.foreground, 1.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Button {
        text: "Sign Out"
        bordered: true
        enabled: panel ? !panel.signingIn : false
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.signOutRequested()
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(8)
      visible: panel ? !panel.signedIn : true

      Text {
        width: parent.width
        text: "Optional. Signing in loads your pull list live for any week, not just the current one. Only the session cookie is stored - never your password - so expired sessions ask you to sign in again."
        color: Qt.darker(root.foreground, 1.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      TextField {
        id: loginNameField
        width: parent.width
        placeholderText: "username"
        color: root.foreground
        font.family: root.fontFamily
        enabled: panel ? !panel.signingIn : true
      }

      TextField {
        id: loginPassField
        width: parent.width
        placeholderText: "password"
        echoMode: TextInput.Password
        passwordCharacter: "\u2022"
        color: root.foreground
        font.family: root.fontFamily
        enabled: panel ? !panel.signingIn : true
        onAccepted: root.signInRequested(loginNameField.text.trim(), loginPassField.text)
      }

      Button {
        text: panel && panel.signingIn ? "\uf252" : "Sign In"
        bordered: true
        enabled: panel ? (!panel.signingIn && loginNameField.text.trim() !== "" && loginPassField.text !== "") : false
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: {
          root.signInRequested(loginNameField.text.trim(), loginPassField.text)
          loginPassField.text = ""
        }
      }
    }

    Text {
      width: parent.width
      visible: panel ? panel.loginStatus !== "" : false
      text: panel ? panel.loginStatus : ""
      color: {
        if (!panel) return Qt.darker(root.foreground, 1.45)
        var bad = panel.loginStatus.indexOf("failed") === 0 ||
          panel.loginStatus.indexOf("Could not") === 0 ||
          panel.loginStatus.indexOf("Sign-in timed out") === 0 ||
          panel.loginStatus.indexOf("The session") === 0 ||
          panel.loginStatus.indexOf("Your session expired") === 0
        return bad ? Color.urgent : Color.accent
      }
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  PanelSeparator { width: parent.width }

  // ---------------------------------------------------------------- storage
  Section {
    title: "Storage"
    width: parent.width
    foreground: root.foreground
    fontFamily: root.fontFamily

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
          return "Off: previous weeks are unavailable anonymously. On: each week's pulls are snapshotted while current, building history over time."
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
  }

  PanelSeparator { width: parent.width }

  // --------------------------------------------------------------- advanced
  Section {
    title: "Advanced"
    width: parent.width
    foreground: root.foreground
    fontFamily: root.fontFamily

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
  }
}
