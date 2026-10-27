import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "HillModel.js" as Model

// One project in the list under the hill: its color, its name, where it
// stands and when it last moved. Hovering a row lights its dot on the hill
// and the other way round; double-clicking the name renames it in place, and
// the actions on the right show up under the pointer.
Item {
  id: row

  required property string pid
  property var panel: null

  readonly property var project: panel ? panel.byId[pid] || null : null
  readonly property bool selected: !!panel && panel.selectedId === pid
  readonly property bool lit: !!panel && panel.hoveredId === pid
  readonly property bool renaming: !!panel && panel.renamingId === pid
  readonly property bool done: !!project && project.progress >= 100
  readonly property bool stale: !!project && !!panel && Model.isStale(project, panel.nowMs, panel.staleDays)
  readonly property color fg: Commons.Color.popups.text
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.55)
  readonly property color tone: panel ? panel.colorOf(project) : Commons.Color.accent
  readonly property bool showActions: hover.hovered && !renaming

  visible: !!project

  component IconAction: Item {
    id: action
    property string glyph: ""
    property string tip: ""
    property color tint: Commons.Color.popups.text
    signal activated()

    width: Style.space(26)
    height: Style.space(24)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: area.containsMouse ? Style.hoverFillFor(action.tint, Commons.Color.accent, Commons.Color.urgent) : "transparent"
    }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: action.glyph
      color: area.containsMouse
        ? Style.hoverStateColor(action.tint, Commons.Color.accent, Commons.Color.urgent)
        : Qt.rgba(action.tint.r, action.tint.g, action.tint.b, 0.7)
      font.family: Style.font.family
      font.pixelSize: Style.font.icon
    }

    MouseArea {
      id: area
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: action.activated()
    }

    PanelToolTip {
      visible: area.containsMouse && action.tip !== ""
      text: action.tip
    }
  }

  // Hover from a handler rather than the row's MouseArea, so moving onto an
  // action button doesn't count as leaving the row and hide the buttons.
  HoverHandler {
    id: hover
    onHoveredChanged: {
      if (!row.panel) return
      if (hovered) row.panel.hoveredId = row.pid
      else if (row.panel.hoveredId === row.pid) row.panel.hoveredId = ""
    }
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: row.selected
      ? Style.selectedFillFor(row.fg, Commons.Color.accent, Commons.Color.urgent)
      : row.lit ? Style.hoverFillFor(row.fg, Commons.Color.accent, Commons.Color.urgent) : "transparent"
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor
    onClicked: row.panel.select(row.pid)
    onDoubleClicked: row.panel.startRename(row.pid)
  }

  // Whether this project's label shows on the hill.
  IconAction {
    id: eye
    x: Style.space(2)
    anchors.verticalCenter: parent.verticalCenter
    glyph: row.panel && row.project ? (row.project.labelHidden ? row.panel.glyphs.labelHidden : row.panel.glyphs.labelShown) : ""
    tip: row.panel && row.project ? row.panel.t(row.project.labelHidden ? "row.labelShow" : "row.labelHide") : ""
    onActivated: row.panel.toggleLabel(row.pid)
  }

  Rectangle {
    id: swatch
    x: eye.x + eye.width + Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(10)
    height: width
    radius: width / 2
    color: row.tone
    opacity: row.done ? 0.55 : 1

    // Clicking the swatch opens the color picker for this project.
    MouseArea {
      id: swatchMouse
      anchors.fill: parent
      anchors.margins: -Style.space(5)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: row.panel.openPicker(row.pid, swatch, swatch.width / 2, swatch.height / 2)
    }

    PanelToolTip {
      visible: swatchMouse.containsMouse
      text: row.panel ? row.panel.t("row.color") : ""
    }
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
    visible: !row.renaming
    anchors.left: swatch.right
    anchors.leftMargin: Style.space(10)
    anchors.right: phaseLabel.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: row.project ? row.project.name : ""
    elide: Text.ElideRight
    color: row.fg
    opacity: row.done ? 0.6 : 1
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    font.bold: row.selected
  }

  TextField {
    id: renameField
    property bool canceled: false

    visible: row.renaming
    // Editable only while the panel shows (see the add field in BarWidget).
    readOnly: !row.panel || !row.panel.opened
    anchors.left: swatch.right
    anchors.leftMargin: Style.space(5)
    anchors.right: phaseLabel.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    verticalPadding: Style.space(3)
    horizontalPadding: Style.space(5)
    maximumLength: Model.MAX_NAME
    foreground: row.fg

    onVisibleChanged: {
      if (!renameField.visible) return
      renameField.canceled = false
      renameField.text = row.project ? row.project.name : ""
      renameField.selectAll()
      renameField.forceActiveFocus()
    }
    Keys.onEscapePressed: function(event) {
      renameField.canceled = true
      row.panel.cancelRename()
      event.accepted = true
    }
    onAccepted: row.panel.commitRename(row.pid, renameField.text, true)
    // Clicking away keeps the new name, the way renaming a file does, and
    // leaves the focus wherever the click put it.
    onActiveFocusChanged: if (!renameField.activeFocus && renameField.visible && !renameField.canceled) row.panel.commitRename(row.pid, renameField.text, false)
  }

  Text {
    id: phaseLabel
    anchors.right: percent.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(124)
    textFormat: Text.PlainText
    text: row.project && row.panel ? row.panel.phaseWord(row.project.progress) : ""
    elide: Text.ElideRight
    color: row.dim
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  Text {
    id: percent
    anchors.right: meta.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(40)
    horizontalAlignment: Text.AlignRight
    textFormat: Text.PlainText
    text: row.project && row.panel ? row.panel.formatPercent(row.project.progress) : ""
    color: row.done ? row.dim : row.fg
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Item {
    id: meta
    anchors.right: parent.right
    anchors.rightMargin: Style.space(4)
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Style.space(84)

    Text {
      id: agoText
      visible: !row.showActions
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: row.project && row.panel ? row.panel.agoText(row.project.updated) : ""
      color: row.stale ? Commons.Color.urgent : row.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption

      HoverHandler { id: agoHover }

      PanelToolTip {
        visible: row.stale && agoHover.hovered
        text: row.panel && row.project ? row.panel.tCount("row.stalled", Model.daysSince(row.project.updated, row.panel.nowMs)) : ""
      }
    }

    Row {
      visible: row.showActions
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      IconAction {
        glyph: row.panel ? row.panel.glyphs.rename : ""
        tip: row.panel ? row.panel.t("row.rename") : ""
        onActivated: row.panel.startRename(row.pid)
      }

      IconAction {
        glyph: row.panel ? (row.done ? row.panel.glyphs.reopen : row.panel.glyphs.done) : ""
        tip: row.panel ? row.panel.t(row.done ? "row.reopen" : "row.done") : ""
        onActivated: row.panel.toggleDone(row.pid)
      }

      IconAction {
        glyph: row.panel ? row.panel.glyphs.remove : ""
        tip: row.panel ? row.panel.t("row.remove") : ""
        tint: Commons.Color.urgent
        onActivated: row.panel.removeProject(row.pid)
      }
    }
  }
}
