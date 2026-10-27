import QtQuick

// A color picker: a square of shades for one hue, and a strip of hues beside
// it. Clicking or dragging in either chooses a color, and `picked` reports it
// when the pointer lets go.
//
// Self-contained (no qs.* imports) so tests/qml can drive it on its own.
Item {
  id: picker

  // The color it opens on. Setting it moves both markers there.
  property color color: "#ff0000"
  property color outline: "#ffffff"
  // The shell's spacing scale, for sizes that follow the theme.
  property real unit: 1
  property int cornerRadius: 4

  property real hue: 0
  property real sat: 1
  property real val: 1
  readonly property color current: Qt.hsva(hue, sat, val, 1)

  signal picked(color value)

  function s(px) { return Math.round(px * unit) }

  function load(c) {
    // A grey has no hue of its own; the strip stays where it was.
    if (c.hsvHue >= 0) hue = c.hsvHue
    sat = c.hsvSaturation
    val = c.hsvValue
  }

  onColorChanged: load(color)
  Component.onCompleted: load(color)

  implicitWidth: shades.width + s(10) + hues.width
  implicitHeight: s(140)

  Rectangle {
    id: shades
    objectName: "shades"
    width: picker.s(200)
    height: picker.height
    radius: picker.cornerRadius
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: "#ffffff" }
      GradientStop { position: 1; color: Qt.hsva(picker.hue, 1, 1, 1) }
    }

    Rectangle {
      anchors.fill: parent
      radius: parent.radius
      gradient: Gradient {
        GradientStop { position: 0; color: "transparent" }
        GradientStop { position: 1; color: "#000000" }
      }
    }

    Rectangle {
      x: picker.sat * shades.width - width / 2
      y: (1 - picker.val) * shades.height - height / 2
      width: picker.s(14)
      height: width
      radius: width / 2
      color: "transparent"
      border.width: 1
      border.color: "#80000000"

      Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: width / 2
        color: picker.current
        border.width: Math.max(1, picker.s(2))
        border.color: picker.outline
      }
    }

    MouseArea {
      anchors.fill: parent
      preventStealing: true
      cursorShape: Qt.CrossCursor

      function take(mouse) {
        picker.sat = Math.max(0, Math.min(1, mouse.x / width))
        picker.val = Math.max(0, Math.min(1, 1 - mouse.y / height))
      }

      onPressed: function(mouse) { take(mouse) }
      onPositionChanged: function(mouse) { if (pressed) take(mouse) }
      onReleased: picker.picked(picker.current)
    }
  }

  Rectangle {
    id: hues
    objectName: "hues"
    x: shades.width + picker.s(10)
    width: picker.s(16)
    height: picker.height
    radius: picker.cornerRadius
    gradient: Gradient {
      GradientStop { position: 0 / 6; color: "#ff0000" }
      GradientStop { position: 1 / 6; color: "#ffff00" }
      GradientStop { position: 2 / 6; color: "#00ff00" }
      GradientStop { position: 3 / 6; color: "#00ffff" }
      GradientStop { position: 4 / 6; color: "#0000ff" }
      GradientStop { position: 5 / 6; color: "#ff00ff" }
      GradientStop { position: 1; color: "#ff0000" }
    }

    Rectangle {
      x: -picker.s(2)
      y: picker.hue * hues.height - height / 2
      width: hues.width + picker.s(4)
      height: picker.s(6)
      radius: height / 2
      color: "transparent"
      border.width: Math.max(1, picker.s(2))
      border.color: picker.outline
    }

    MouseArea {
      anchors.fill: parent
      preventStealing: true
      cursorShape: Qt.PointingHandCursor

      function take(mouse) { picker.hue = Math.max(0, Math.min(1, mouse.y / height)) }

      onPressed: function(mouse) { take(mouse) }
      onPositionChanged: function(mouse) { if (pressed) take(mouse) }
      onReleased: picker.picked(picker.current)
    }
  }
}
