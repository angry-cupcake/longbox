import QtQuick
import qs.Commons

// Poster-grid view: about three medium covers per row with title and
// publisher beneath, plus the same hover mark actions as the list view.
// Non-scrolling: the host panel's Flickable owns scrolling, so the grid is
// sized to its full content height.
GridView {
  id: root

  property var panel: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal issueActivated(int index)

  interactive: false
  clip: false
  boundsBehavior: Flickable.StopAtBounds

  cellWidth: width / 3
  cellHeight: cellWidth * 1.72

  delegate: Item {
    id: cell

    required property var modelData
    required property int index

    readonly property var mark: panel ? (panel.doc.marks[modelData.id] || null) : null
    readonly property bool isCollected: mark ? !!mark.collected : false
    readonly property bool isRead: mark ? !!mark.readAt : false
    readonly property bool isWished: mark ? !!mark.wishlist : false

    width: root.cellWidth
    height: root.cellHeight

    Column {
      width: parent.width - Style.space(12)
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(4)

      Item {
        id: coverSlot
        width: parent.width
        height: width * 1.5

        Image {
          anchors.fill: parent
          asynchronous: true
          fillMode: Image.PreserveAspectCrop
          source: cell.modelData.cover !== "" ? cell.modelData.cover : ""
        }

        Rectangle {
          anchors.fill: parent
          color: "transparent"
          radius: Style.space(3)
          border.color: cellMouse.containsMouse ? Qt.darker(root.foreground, 1.4) : "transparent"
          border.width: 1
        }

        Text {
          visible: cell.isCollected
          text: "\uf00c"
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: Style.space(3)
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: cell.isWished
          text: "\uf005"
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(3)
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // Hover actions overlay the cover's top-left corner.
        Row {
          spacing: Style.space(6)
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.margins: Style.space(4)
          opacity: cellMouse.containsMouse ? 1 : 0

          MarkGlyph {
            foreground: root.foreground
            activeMark: cell.isCollected
            text: "\uf00c"
            onActivated: if (panel) panel.toggleMark(cell.modelData.id, "collected")
          }

          MarkGlyph {
            foreground: root.foreground
            activeMark: cell.isRead
            text: "\uf06e"
            onActivated: if (panel) panel.toggleMark(cell.modelData.id, "read")
          }

          MarkGlyph {
            foreground: root.foreground
            activeMark: cell.isWished
            text: "\uf005"
            onActivated: if (panel) panel.toggleMark(cell.modelData.id, "wishlist")
          }
        }
      }

      Text {
        width: parent.width
        text: modelData.title
        color: cell.isRead ? Qt.darker(root.foreground, 2.1) : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        wrapMode: Text.NoWrap
        maximumLineCount: 2
      }

      Text {
        width: parent.width
        text: {
          var parts = []
          if (modelData.publisher !== "") parts.push(modelData.publisher)
          if (modelData.price !== "") parts.push(modelData.price)
          return parts.join(" · ")
        }
        color: Qt.darker(root.foreground, 1.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    MouseArea {
      id: cellMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.issueActivated(cell.index)
      onContainsMouseChanged: {
        if (!panel) return
        if (containsMouse) panel.showComicTip(cell.modelData, cell)
        else panel.hideComicTip(cell)
      }
    }
  }
}
