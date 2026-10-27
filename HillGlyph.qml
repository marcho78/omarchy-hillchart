import QtQuick
import QtQuick.Shapes
import "HillModel.js" as Model

// One project's place on the hill at the size of a word: the hill, the way
// already climbed drawn in the project's color, and the project where it
// stands. A column of these reads like a table of sparklines.
Item {
  id: glyph

  property int progress: 0
  property color tone: "#7aa2f7"
  property color lineColor: "#cdd6f4"
  property color ringColor: "transparent"
  property real dotSize: 6
  property real lineWidth: 1.25
  property bool reduceMotion: false

  property real shown: progress
  Behavior on shown { NumberAnimation { duration: glyph.reduceMotion ? 0 : 450; easing.type: Easing.OutCubic } }

  readonly property var box: ({ x: dotSize / 2, y: dotSize / 2, width: Math.max(1, width - dotSize), height: Math.max(1, height - dotSize) })
  readonly property var pt: Model.point(shown, box)

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: glyph.lineColor
      strokeWidth: glyph.lineWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathPolyline { path: Model.outline(glyph.box, 40).map(function(p) { return Qt.point(p.x, p.y) }) }
    }
  }

  Shape {
    anchors.fill: parent
    visible: glyph.shown > 0
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: glyph.tone
      strokeWidth: glyph.lineWidth * 1.6
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathPolyline { path: Model.outlineTo(glyph.box, 40, glyph.shown).map(function(p) { return Qt.point(p.x, p.y) }) }
    }
  }

  Rectangle {
    x: glyph.pt.x - width / 2
    y: glyph.pt.y - height / 2
    width: glyph.dotSize
    height: width
    radius: width / 2
    color: glyph.tone
    border.width: glyph.ringColor.a > 0 ? 1 : 0
    border.color: glyph.ringColor
  }
}
