pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "HillModel.js" as Model

// What hovering the bar hill shows: every project with a little hill of its
// own, so which dot is which, and how far each has come, reads at a glance.
// It is passive: it waits for the pointer to settle, leaves with it, and a
// click opens the full hill instead.
PopupCard {
  id: peek

  property var panel: null

  readonly property int maxRows: 8
  readonly property var list: panel ? panel.orderedProjects : []
  readonly property color fg: Commons.Color.popups.text
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.55)
  readonly property int rowHeight: Style.space(26)

  triggerMode: "hover"
  contentWidth: Style.space(330)
  contentHeight: peek.fittedContentHeight(body.implicitHeight)

  Column {
    id: body
    width: parent.width
    spacing: Style.space(8)

    Item {
      width: parent.width
      implicitHeight: title.implicitHeight

      Text {
        id: title
        anchors.left: parent.left
        textFormat: Text.PlainText
        text: peek.panel ? peek.panel.t("title") : ""
        color: peek.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Row {
        anchors.right: parent.right
        anchors.baseline: title.baseline
        // A Row has no baseline of its own; lend it its text's.
        baselineOffset: countText.baselineOffset
        spacing: Style.space(6)

        Text {
          id: countText
          visible: peek.list.length > 0
          textFormat: Text.PlainText
          text: peek.panel ? peek.panel.tCount("summary.projects", peek.list.length) : ""
          color: peek.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: !!peek.panel && peek.panel.stalledCount > 0
          textFormat: Text.PlainText
          text: peek.panel && peek.panel.stalledCount > 0 ? "· " + peek.panel.tArg("summary.stalled", peek.panel.fmt(peek.panel.stalledCount)) : ""
          color: Commons.Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }

    Column {
      width: parent.width
      visible: peek.list.length > 0

      Repeater {
        model: peek.list.slice(0, peek.maxRows)

        Item {
          id: row
          required property var modelData
          required property int index
          readonly property bool done: modelData.progress >= 100
          readonly property bool stale: !!peek.panel && Model.isStale(modelData, peek.panel.nowMs, peek.panel.staleDays)
          readonly property color tone: peek.panel ? peek.panel.colorOf(modelData) : Commons.Color.accent

          width: parent.width
          height: peek.rowHeight
          transform: Translate { id: slide }

          // Rows arrive one after another as the card fades in.
          SequentialAnimation {
            id: enter
            PropertyAction { target: row; property: "opacity"; value: 0 }
            PropertyAction { target: slide; property: "x"; value: -Style.space(8) }
            PauseAnimation { duration: Style.duration(row.index * 24) }
            ParallelAnimation {
              NumberAnimation { target: row; property: "opacity"; to: 1; duration: Style.duration(180); easing.type: Easing.OutCubic }
              NumberAnimation { target: slide; property: "x"; to: 0; duration: Style.duration(240); easing.type: Easing.OutCubic }
            }
          }

          Connections {
            target: peek
            function onOpenChanged() { if (peek.open) enter.restart() }
          }

          Rectangle {
            id: swatch
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(8)
            height: width
            radius: width / 2
            color: row.tone
            opacity: row.done ? 0.55 : 1
          }

          Rectangle {
            visible: row.stale
            anchors.centerIn: swatch
            width: swatch.width + Style.space(6)
            height: width
            radius: width / 2
            color: "transparent"
            border.width: Math.max(1, Style.space(1.5))
            border.color: Commons.Color.urgent
          }

          Text {
            anchors.left: swatch.right
            anchors.leftMargin: Style.space(10)
            anchors.right: glyph.left
            anchors.rightMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: row.modelData.name
            elide: Text.ElideRight
            color: peek.fg
            opacity: row.done ? 0.6 : 1
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          HillGlyph {
            id: glyph
            anchors.right: percent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(58)
            height: Style.space(16)
            progress: row.modelData.progress
            tone: row.tone
            lineColor: Qt.rgba(peek.fg.r, peek.fg.g, peek.fg.b, 0.22)
            ringColor: Commons.Color.popups.background
            dotSize: Style.space(7)
            lineWidth: Math.max(1, Style.spaceReal(1.25))
            reduceMotion: Style.reduceMotion
            opacity: row.done ? 0.6 : 1
          }

          Text {
            id: percent
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(34)
            horizontalAlignment: Text.AlignRight
            textFormat: Text.PlainText
            text: row.done ? "✓" : (peek.panel ? peek.panel.formatPercent(row.modelData.progress) : "")
            color: row.stale ? Commons.Color.urgent : row.done ? row.tone : peek.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    Text {
      visible: peek.list.length > peek.maxRows
      textFormat: Text.PlainText
      text: peek.panel && peek.list.length > peek.maxRows ? peek.panel.tCount("peek.more", peek.list.length - peek.maxRows) : ""
      color: peek.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Text {
      visible: peek.list.length === 0
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: peek.panel ? peek.panel.t("peek.empty") : ""
      color: peek.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }
}
