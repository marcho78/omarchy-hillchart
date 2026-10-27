pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "HillModel.js" as Model

// The hill at bar size: the curve and a dot per project. Nothing to read,
// just where things stand and whether they are moving: dots glide to their
// new spots when anything changes, wherever it was changed from.
Item {
  id: mini

  property var model: null
  property var byId: ({})
  property var swatches: Model.FALLBACK_PALETTE
  property color lineColor: "#cdd6f4"
  // The bar's own background, as a hairline around each dot so dots that
  // stand together stay apart.
  property color ringColor: "transparent"
  property real dotSize: 5
  property real lineWidth: 1.25
  property bool reduceMotion: false

  readonly property var box: ({ x: dotSize / 2, y: dotSize / 2, width: Math.max(1, width - dotSize), height: Math.max(1, height - dotSize) })
  readonly property var outline: Model.outline(box, 48).map(function(pt) { return Qt.point(pt.x, pt.y) })

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: mini.lineColor
      strokeWidth: mini.lineWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathPolyline { path: mini.outline }
    }
  }

  Repeater {
    model: mini.model

    delegate: Rectangle {
      id: dot
      required property string pid
      readonly property var project: mini.byId[pid] || null
      property real shown: project ? project.progress : 0
      Behavior on shown { NumberAnimation { duration: mini.reduceMotion ? 0 : 450; easing.type: Easing.OutCubic } }
      readonly property var pt: Model.point(shown, mini.box)

      visible: !!project
      x: pt.x - width / 2
      y: pt.y - height / 2
      // Further along draws on top, the way the eye reads the hill.
      z: shown
      width: mini.dotSize
      height: width
      radius: width / 2
      color: Model.colorFor(project, mini.swatches)
      border.width: mini.ringColor.a > 0 ? 1 : 0
      border.color: mini.ringColor
      opacity: project && project.progress >= 100 ? 0.55 : 1
    }
  }
}
