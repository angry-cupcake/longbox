import QtQuick
import qs.Commons

// Small clickable mark icon used by the list and grid views to toggle
// local collection state. Lights up accent-colored while active.
Text {
  id: glyph

  property bool activeMark: false
  property color foreground: Color.foreground

  signal activated()

  font.family: Style.font.family
  font.pixelSize: Style.font.body
  color: activeMark ? Color.accent : Qt.darker(foreground, 1.7)

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: glyph.activated()
  }
}
