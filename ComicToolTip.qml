import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Rich hover preview for a single comic. A Popup rather than a plain Item so
// it paints above the panel's clipped Flickable without being cut off.
// Content: cover thumbnail beside title, details, release info, and a click
// hint pointing at the LoCG page.
Popup {
  id: root

  property var issue: null
  property string fontFamily: Style.font.family

  closePolicy: Popup.NoAutoClose
  modal: false
  dim: false
  padding: Style.space(10)

  background: BorderSurface {
    color: Color.tooltip.background
    borderSpec: Border.localOrSurfaceSpec("tooltip", "border",
      Color.tooltip.border, Color.tooltip.border, Style.normalBorderWidth)
    radius: Style.cornerRadius
  }

  contentItem: Row {
    spacing: Style.space(10)

    Image {
      width: Style.space(50)
      height: Style.space(76)
      anchors.verticalCenter: parent.verticalCenter
      asynchronous: true
      fillMode: Image.PreserveAspectCrop
      source: root.issue && root.issue.cover !== "" ? root.issue.cover : ""
      visible: root.issue !== null
    }

    Column {
      width: Style.space(228)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)

      Text {
        width: parent.width
        text: root.issue ? Model.cleanText(root.issue.title) : ""
        color: Color.tooltip.text
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: {
          if (!root.issue) return ""
          var parts = []
          if (root.issue.publisher !== "") parts.push(Model.cleanText(root.issue.publisher))
          if (root.issue.price !== "") parts.push(root.issue.price)
          return parts.join(" · ")
        }
        color: Qt.darker(Color.tooltip.text, 1.35)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: {
          if (!root.issue) return ""
          var label = Model.weekLabel(root.issue.releaseTs)
          var days = Model.daysUntil(root.issue.releaseTs)
          if (days !== null && days <= 0) return "Out now, shipped " + label
          return "Ships " + label
        }
        color: Qt.darker(Color.tooltip.text, 1.35)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: "Click to open on League of Comic Geeks"
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }
}
