pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "HillModel.js" as Model

// The hill: the curve, a dot for each project standing on it, and a name tag
// beside each dot. A dot (or its tag) is grabbed and dragged along the curve,
// and it rides the slope rather than the pointer, so it can only ever be
// somewhere on the hill. Empty hill is a place to double-click a new project
// onto, right where it already stands.
//
// Self-contained on purpose: no qs.* imports. The panel hands in colors,
// fonts and words, and tests/qml drives it on its own.
Item {
  id: hill

  // ---- Data, owned by the panel. `model` holds { pid } rows and only
  //      changes when projects come or go, so a dot that moves keeps its
  //      delegate (and its animation) instead of being rebuilt.
  property var model: null
  property var byId: ({})
  property var swatches: Model.FALLBACK_PALETTE
  property string selectedId: ""
  property string hoveredId: ""
  property int ghostProgress: -1
  property real nowMs: Date.now()
  property int staleDays: 7

  // ---- Look
  property color foreground: "#cdd6f4"
  property color background: "#1e1e2e"
  property color accent: "#89b4fa"
  property color urgent: "#f38ba8"
  property string fontFamily: "monospace"
  property int fontSize: 11
  property int captionSize: 10
  // The shell's spacing scale, for sizes that follow the theme.
  property real unit: 1
  property int cornerRadius: 6
  property bool reduceMotion: false
  // False while the panel is closed: nothing pulses on a hill nobody sees.
  property bool live: true

  // ---- Words. `host` may supply phaseWord(progress) and
  //      formatPercent(progress) in the user's language.
  property string uphillLabel: "FIGURING THINGS OUT"
  property string downhillLabel: "MAKING IT HAPPEN"
  property string bubbleFormat: "%1 · %2"
  property var host: null

  signal selectRequested(string id)
  signal hoverRequested(string id)
  signal moveRequested(string id, int progress)
  // Double-clicking a dot toggles its label; double-clicking a label hides it.
  signal labelToggleRequested(string id)
  signal labelHideRequested(string id)
  // Right-clicking a dot asks for its color picker, at (x, y) on the hill.
  signal colorRequested(string id, real x, real y)
  signal addRequested(int progress)
  signal clearRequested()
  // Any press on the hill: the panel takes keyboard focus back from a text
  // field, so the arrow keys move dots again.
  signal interacted()

  // ---- Drag state. While a dot is held it shows dragProgress; the project
  //      itself only changes on release.
  property string dragId: ""
  property int dragProgress: 0
  property real dragOffset: 0
  property real pressX: 0
  property string pressId: ""
  readonly property bool dragging: dragId !== ""
  readonly property string focusId: dragId || hoveredId || selectedId

  function s(px) { return Math.round(px * unit) }
  function ms(duration) { return reduceMotion ? 0 : duration }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function colorOf(project) { return Model.colorFor(project, swatches) }
  function percentText(p) { return host && host.formatPercent ? host.formatPercent(p) : p + "%" }
  function phaseText(p) {
    if (host && host.phaseWord) return host.phaseWord(p)
    return p >= 100 ? "Done" : p === 50 ? "Over the top" : p > 50 ? "Making it happen" : "Figuring it out"
  }

  // ---- Geometry. The box is where the curve lives: its bottom edge is the
  //      ground, the space above holds tags around the top, and the strip
  //      below holds the two phase labels.
  readonly property int dotSize: hill.s(12)
  readonly property int hitSize: hill.s(30)
  readonly property int padX: hill.s(24)
  readonly property int padTop: hill.s(34)
  readonly property int groundGap: hill.s(30)
  readonly property var box: ({ x: padX, y: padTop, width: Math.max(1, width - padX * 2), height: Math.max(1, height - padTop - groundGap) })
  readonly property real groundY: box.y + box.height
  readonly property var outline: Model.outline(box, 120).map(function(pt) { return Qt.point(pt.x, pt.y) })
  readonly property var peak: Model.point(50, box)

  // ---- Drag, shared by the dots and their tags.
  function beginPress(id, x) {
    hill.interacted()
    hill.pressId = id
    hill.pressX = x
    hill.selectRequested(id)
  }

  function dragTo(id, x) {
    if (hill.pressId !== id) return
    if (hill.dragId !== id) {
      // A few pixels of slop first, so a click on a dot is only a click.
      if (Math.abs(x - hill.pressX) < hill.s(3)) return
      let project = hill.byId[id]
      let start = project ? project.progress : 0
      // Keep the dot where it was under the pointer instead of snapping
      // its center to it.
      hill.dragOffset = Model.point(start, hill.box).x - hill.pressX
      hill.dragProgress = start
      hill.dragId = id
    }
    hill.dragProgress = Model.progressAt(x + hill.dragOffset, hill.box)
  }

  function endPress(id, commit) {
    if (hill.pressId === id) hill.pressId = ""
    if (hill.dragId !== id) return
    // Report first: the panel moves the project synchronously, so when the
    // drag lets go the dot is already where it was dropped.
    if (commit) hill.moveRequested(id, hill.dragProgress)
    hill.dragId = ""
  }

  // A little celebration on the dot: a ring for cresting the top, a burst for
  // reaching done.
  function celebrate(id, kind) {
    let d = hill.dotItems[id]
    if (d) d.celebrate(kind)
  }

  // Each project's dot, for celebrate(). The dots add and remove themselves.
  property var dotItems: ({})

  // ---- Name tags, laid out from where projects stand (not where a held dot
  //      is), so the others hold still while one is being dragged.
  readonly property int tagHeight: Math.round(tagMetrics.height + hill.s(6))
  readonly property int tagMaxChars: 22
  readonly property int tagPadX: hill.s(7)

  function tagLabel(project) { return Model.elide(project ? project.name : "", hill.tagMaxChars) }
  function tagWidth(project) { return Math.ceil(tagMetrics.advanceWidth(tagLabel(project))) + tagPadX * 2 + hill.s(4) }

  readonly property var tagLayout: {
    var items = []
    var count = hill.model ? hill.model.count : 0
    for (let i = 0; i < count; i++) {
      let id = hill.model.get(i).pid
      let p = hill.byId[id]
      if (!p) continue
      let pt = Model.point(p.progress, hill.box)
      // A project whose label is hidden is still a dot other labels keep
      // clear of.
      items.push({ id: id, x: pt.x, y: pt.y, w: hill.tagWidth(p), h: hill.tagHeight, uphill: p.progress < 50, tag: !p.labelHidden })
    }
    var bounds = { x: hill.s(2), y: hill.s(2), w: hill.width - hill.s(4), h: hill.groundY + hill.tagHeight / 2 + hill.s(2) }
    return Model.layoutTags(items, bounds, hill.s(6), hill.dotSize + hill.s(6), hill.phaseRects)
  }

  // The phase labels under the ground stay readable: no tag may cover them.
  readonly property var phaseRects: [uphillText, downhillText].map(function(t) {
    return { x: t.x - hill.s(4), y: t.y, w: t.width + hill.s(8), h: t.height }
  })

  FontMetrics {
    id: tagMetrics
    font.family: hill.fontFamily
    font.pixelSize: hill.fontSize
  }

  // ---- The ground and the hill

  // Light under the hill, strongest at the top.
  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: "transparent"
      strokeWidth: 0
      fillGradient: LinearGradient {
        x1: 0; y1: hill.box.y
        x2: 0; y2: hill.groundY
        GradientStop { position: 0; color: hill.alpha(hill.accent, 0.22) }
        GradientStop { position: 1; color: hill.alpha(hill.accent, 0.02) }
      }
      PathPolyline { path: hill.outline }
    }
  }

  Rectangle {
    x: 0
    y: Math.round(hill.groundY)
    width: hill.width
    height: Math.max(1, hill.s(1))
    color: hill.alpha(hill.foreground, 0.10)
  }

  // The top of the hill: once a project is past this line, nothing about it
  // is unknown any more. It lights up while a held dot sits right on it.
  Shape {
    id: peakLine
    readonly property bool lit: hill.dragging && hill.dragProgress === 50
    anchors.fill: parent
    ShapePath {
      strokeColor: peakLine.lit ? hill.accent : hill.alpha(hill.foreground, 0.22)
      strokeWidth: Math.max(1, hill.unit)
      strokeStyle: ShapePath.DashLine
      dashPattern: [2, 3]
      fillColor: "transparent"
      startX: Math.round(hill.peak.x) + 0.5
      startY: hill.peak.y
      PathLine { x: Math.round(hill.peak.x) + 0.5; y: hill.groundY }
    }
  }

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: hill.alpha(hill.foreground, 0.58)
      strokeWidth: Math.max(1.5, 2 * hill.unit)
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathPolyline { path: hill.outline }
    }
  }

  Text {
    id: uphillText
    textFormat: Text.PlainText
    x: Math.round(hill.box.x + hill.box.width * 0.25 - width / 2)
    // Low enough that a name beside a dot at the foot clears it.
    y: Math.round(hill.groundY + hill.tagHeight / 2 + hill.s(2))
    text: hill.uphillLabel
    color: hill.alpha(hill.foreground, 0.42)
    font.family: hill.fontFamily
    font.pixelSize: hill.captionSize
    font.letterSpacing: 1.2
  }

  Text {
    id: downhillText
    textFormat: Text.PlainText
    x: Math.round(hill.box.x + hill.box.width * 0.75 - width / 2)
    y: uphillText.y
    text: hill.downhillLabel
    color: uphillText.color
    font: uphillText.font
  }

  // ---- Empty hill: double-click to add, click to let go of the selection.
  MouseArea {
    id: ground
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    property real hoverX: -1
    onPositionChanged: function(mouse) { hoverX = mouse.x }
    onExited: hoverX = -1
    onPressed: hill.interacted()
    onClicked: hill.clearRequested()
    onDoubleClicked: function(mouse) { hill.addRequested(Model.progressAt(mouse.x, hill.box)) }
  }

  // Where a project would land: follows the pointer along the curve so the
  // hill reads as something to put things on.
  Rectangle {
    readonly property int at: Model.progressAt(ground.hoverX, hill.box)
    readonly property var pt: Model.point(at, hill.box)
    visible: ground.containsMouse && ground.hoverX >= 0 && !hill.dragging && hill.ghostProgress < 0 && hill.hoveredId === ""
    x: pt.x - width / 2
    y: pt.y - height / 2
    width: hill.dotSize
    height: width
    radius: width / 2
    color: "transparent"
    border.width: Math.max(1, hill.s(1.5))
    border.color: hill.alpha(hill.foreground, 0.45)

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: "+"
      color: hill.alpha(hill.foreground, 0.6)
      font.family: hill.fontFamily
      font.pixelSize: Math.max(8, parent.width * 0.8)
    }
  }

  // ---- Where the focused project has been: earlier stops, fading with age.
  Repeater {
    id: trail
    model: {
      var p = hill.byId[hill.focusId]
      return p ? Model.trail(p, 6) : []
    }

    Rectangle {
      required property int modelData
      required property int index
      readonly property var pt: Model.point(modelData, hill.box)
      x: pt.x - width / 2
      y: pt.y - height / 2
      width: hill.s(6)
      height: width
      radius: width / 2
      color: hill.colorOf(hill.byId[hill.focusId])
      opacity: 0.18 + 0.32 * (index + 1) / Math.max(1, trail.count)
    }
  }

  // A new project waiting for its name, where the hill was double-clicked
  // (or at the foot of an empty hill, as an invitation).
  Rectangle {
    id: ghost
    readonly property int at: hill.ghostProgress >= 0 ? hill.ghostProgress : 0
    readonly property var pt: Model.point(at, hill.box)
    visible: hill.ghostProgress >= 0 || (dots.count === 0 && !ground.containsMouse)
    x: pt.x - width / 2
    y: pt.y - height / 2
    width: hill.dotSize + hill.s(2)
    height: width
    radius: width / 2
    color: hill.alpha(hill.accent, 0.18)
    border.width: Math.max(1, hill.s(2))
    border.color: hill.accent

    SequentialAnimation on opacity {
      running: ghost.visible && hill.live && !hill.reduceMotion
      loops: Animation.Infinite
      NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
    }
  }

  // ---- Name tags. Under the dots, so a dot is never hidden by a label.
  Repeater {
    id: tags
    model: hill.model

    delegate: Rectangle {
      id: tag
      required property string pid
      readonly property var project: hill.byId[pid] || null
      readonly property var entry: hill.tagLayout[pid] || null
      readonly property bool active: hill.selectedId === pid || hill.hoveredId === pid
      readonly property bool held: hill.dragId === pid
      // Hidden labels get no place on the hill.
      readonly property bool shown: !!project && !!entry
      readonly property color tone: hill.colorOf(project)

      // Its last place. A tag that loses its place fades out where it stood
      // rather than jumping somewhere first.
      property real spotX: 0
      property real spotY: 0
      property real spotW: 0
      property real spotH: 0

      function takeSpot() {
        if (!entry) return
        spotX = entry.x
        spotY = entry.y
        spotW = entry.w
        spotH = entry.h
      }

      onEntryChanged: takeSpot()
      Component.onCompleted: takeSpot()

      objectName: "tag-" + pid
      // Faded rather than hidden, whether its label was hidden or while its
      // dot is held (the bubble names it then): a hidden item drops the
      // pointer grab, which would end a drag that started on the tag.
      visible: !!project
      x: spotX
      y: spotY
      width: spotW
      height: spotH
      z: active ? 2 : 1
      radius: Math.min(hill.cornerRadius, height / 2)
      color: hill.alpha(hill.background, 0.92)
      border.width: 1
      border.color: hill.alpha(tone, active ? 0.95 : 0.4)
      opacity: held || !shown ? 0 : project.progress >= 100 && !active ? 0.7 : 1

      Behavior on opacity { NumberAnimation { duration: hill.ms(140); easing.type: Easing.OutCubic } }
      // Glide while rearranging in view; arrive in place when coming into it.
      Behavior on x { enabled: tag.opacity > 0.5; NumberAnimation { duration: hill.ms(220); easing.type: Easing.OutCubic } }
      Behavior on y { enabled: tag.opacity > 0.5; NumberAnimation { duration: hill.ms(220); easing.type: Easing.OutCubic } }

      Rectangle {
        x: hill.tagPadX - hill.s(1)
        anchors.verticalCenter: parent.verticalCenter
        width: hill.s(3)
        height: parent.height - hill.s(8)
        radius: width / 2
        color: tag.tone
      }

      Text {
        textFormat: Text.PlainText
        x: hill.tagPadX + hill.s(5)
        anchors.verticalCenter: parent.verticalCenter
        text: hill.tagLabel(tag.project)
        color: hill.foreground
        font.family: hill.fontFamily
        font.pixelSize: hill.fontSize
        font.bold: tag.active
      }

      MouseArea {
        anchors.fill: parent
        // A hidden label must not catch the pointer meant for what is under it.
        enabled: tag.shown || tag.held
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.OpenHandCursor
        onEntered: hill.hoverRequested(tag.pid)
        onExited: if (hill.hoveredId === tag.pid) hill.hoverRequested("")
        onPressed: function(mouse) { hill.beginPress(tag.pid, mapToItem(hill, mouse.x, mouse.y).x) }
        onPositionChanged: function(mouse) { if (pressed) hill.dragTo(tag.pid, mapToItem(hill, mouse.x, mouse.y).x) }
        onReleased: hill.endPress(tag.pid, true)
        onCanceled: hill.endPress(tag.pid, false)
        onDoubleClicked: hill.labelHideRequested(tag.pid)
      }
    }
  }

  // ---- The dots.
  Repeater {
    id: dots
    model: hill.model

    delegate: Item {
      id: dot
      required property string pid
      readonly property var project: hill.byId[pid] || null
      readonly property bool held: hill.dragId === pid
      readonly property bool selected: hill.selectedId === pid
      readonly property bool hovered: hill.hoveredId === pid
      readonly property bool done: !!project && project.progress >= 100
      readonly property bool stale: !!project && Model.isStale(project, hill.nowMs, hill.staleDays)
      readonly property color tone: hill.colorOf(project)

      // Where the dot is drawn. It eases between positions, and because the
      // point is recomputed from the curve at every step, a dot nudged by
      // the keyboard (or moved by an undo, or another bar) walks along the
      // hill instead of cutting through it.
      property real shown: held ? hill.dragProgress : (project ? project.progress : 0)
      Behavior on shown {
        enabled: !dot.held
        NumberAnimation { duration: hill.ms(320); easing.type: Easing.OutCubic }
      }
      readonly property var pt: Model.point(shown, hill.box)

      function celebrate(kind) {
        ring.big = kind === "done"
        ringAnim.restart()
        if (kind === "done") burstAnim.restart()
      }

      Component.onCompleted: hill.dotItems[dot.pid] = dot
      Component.onDestruction: if (hill.dotItems[dot.pid] === dot) delete hill.dotItems[dot.pid]

      visible: !!project
      x: pt.x
      y: pt.y
      z: held ? 30 : selected ? 20 : hovered ? 15 : 10

      Rectangle {
        anchors.centerIn: parent
        width: hill.dotSize * 2.4
        height: width
        radius: width / 2
        color: dot.tone
        opacity: dot.held ? 0.3 : dot.selected ? 0.2 : 0
        Behavior on opacity { NumberAnimation { duration: hill.ms(160) } }
      }

      // A project that hasn't moved in a while wears a warning ring.
      Rectangle {
        anchors.centerIn: parent
        visible: dot.stale
        width: core.width + hill.s(7)
        height: width
        radius: width / 2
        color: "transparent"
        border.width: Math.max(1, hill.s(1.5))
        border.color: hill.urgent
        opacity: 0.9
      }

      Rectangle {
        id: core
        anchors.centerIn: parent
        width: hill.dotSize * (dot.held ? 1.45 : dot.selected ? 1.25 : dot.hovered ? 1.15 : 1)
        height: width
        radius: width / 2
        color: dot.tone
        border.width: Math.max(1.5, 2 * hill.unit)
        border.color: hill.background
        Behavior on width { NumberAnimation { duration: hill.ms(150); easing.type: Easing.OutBack } }

        Text {
          anchors.centerIn: parent
          visible: dot.done
          textFormat: Text.PlainText
          text: "✓"
          color: hill.background
          font.pixelSize: Math.max(7, parent.width * 0.6)
          font.bold: true
        }
      }

      Rectangle {
        id: ring
        property bool big: false
        anchors.centerIn: parent
        width: hill.dotSize
        height: width
        radius: width / 2
        color: "transparent"
        border.width: Math.max(1, hill.s(2))
        border.color: dot.tone
        opacity: 0

        ParallelAnimation {
          id: ringAnim
          NumberAnimation { target: ring; property: "scale"; from: 1; to: ring.big ? 4.4 : 3.4; duration: hill.ms(700); easing.type: Easing.OutCubic }
          NumberAnimation { target: ring; property: "opacity"; from: 0.95; to: 0; duration: hill.ms(700); easing.type: Easing.OutCubic }
        }
      }

      Item {
        id: burst
        property real t: 0
        visible: t > 0 && t < 1

        Repeater {
          model: 10

          Rectangle {
            required property int index
            readonly property real angle: index / 10 * Math.PI * 2 - Math.PI / 2
            width: hill.s(4)
            height: width
            radius: width / 2
            color: index % 2 ? dot.tone : hill.accent
            x: Math.cos(angle) * burst.t * hill.s(26) - width / 2
            y: Math.sin(angle) * burst.t * hill.s(26) - height / 2
            opacity: 1 - burst.t
          }
        }

        NumberAnimation on t {
          id: burstAnim
          running: false
          from: 0
          to: 1
          duration: hill.ms(800)
          easing.type: Easing.OutQuad
        }
      }

      MouseArea {
        id: grab
        anchors.centerIn: parent
        width: hill.hitSize
        height: hill.hitSize
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        preventStealing: true
        cursorShape: dot.held ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        onEntered: hill.hoverRequested(dot.pid)
        onExited: if (hill.hoveredId === dot.pid) hill.hoverRequested("")
        onPressed: function(mouse) {
          var at = mapToItem(hill, mouse.x, mouse.y)
          if (mouse.button === Qt.RightButton) {
            hill.interacted()
            hill.colorRequested(dot.pid, at.x, at.y)
            return
          }
          hill.beginPress(dot.pid, at.x)
        }
        onPositionChanged: function(mouse) {
          if (pressedButtons & Qt.LeftButton) hill.dragTo(dot.pid, mapToItem(hill, mouse.x, mouse.y).x)
        }
        onReleased: function(mouse) { if (mouse.button === Qt.LeftButton) hill.endPress(dot.pid, true) }
        onCanceled: hill.endPress(dot.pid, false)
        onDoubleClicked: function(mouse) { if (mouse.button === Qt.LeftButton) hill.labelToggleRequested(dot.pid) }
      }
    }
  }

  // ---- While a dot is held: what it is and where it would land.
  Rectangle {
    id: bubble
    readonly property var project: hill.byId[hill.dragId] || null
    readonly property var pt: Model.point(hill.dragProgress, hill.box)
    readonly property real above: pt.y - hill.dotSize - hill.s(12) - height
    visible: hill.dragging && !!project
    z: 40
    width: bubbleColumn.implicitWidth + hill.s(18)
    height: bubbleColumn.implicitHeight + hill.s(10)
    x: Math.max(hill.s(2), Math.min(pt.x - width / 2, hill.width - width - hill.s(2)))
    y: above >= 0 ? above : pt.y + hill.dotSize + hill.s(12)
    radius: Math.min(hill.cornerRadius, hill.s(8))
    color: hill.background
    border.width: 1
    border.color: hill.colorOf(project)

    Column {
      id: bubbleColumn
      anchors.centerIn: parent
      spacing: hill.s(1)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: Model.elide(bubble.project ? bubble.project.name : "", 32)
        color: hill.foreground
        font.family: hill.fontFamily
        font.pixelSize: hill.fontSize
        font.bold: true
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: hill.bubbleFormat.arg(hill.percentText(hill.dragProgress)).arg(hill.phaseText(hill.dragProgress))
        color: hill.alpha(hill.foreground, 0.7)
        font.family: hill.fontFamily
        font.pixelSize: hill.captionSize
      }
    }
  }
}
