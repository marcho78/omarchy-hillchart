import QtQuick
import QtTest
import "../.."
import "../../HillModel.js" as Model

// HillGlyph: one project's spot on a word-sized hill.
Item {
  width: 120
  height: 40

  HillGlyph {
    id: glyph
    width: 60
    height: 16
    reduceMotion: true
  }

  TestCase {
    name: "HillGlyph"
    when: windowShown

    function dot() {
      for (var i = 0; i < glyph.children.length; i++) {
        var c = glyph.children[i]
        if (c.radius !== undefined && c.width === glyph.dotSize) return c
      }
      return null
    }

    function test_the_dot_stands_where_the_project_does() {
      var values = [0, 30, 50, 75, 100]
      for (var i = 0; i < values.length; i++) {
        glyph.progress = values[i]
        wait(0)
        var expected = Model.point(values[i], glyph.box)
        var d = dot()
        verify(d)
        fuzzyCompare(d.x + d.width / 2, expected.x, 0.01)
        fuzzyCompare(d.y + d.height / 2, expected.y, 0.01)
      }
    }

    function test_the_top_of_the_hill_is_the_top_of_the_glyph() {
      glyph.progress = 50
      wait(0)
      fuzzyCompare(dot().y, 0, 0.01)
      glyph.progress = 0
      wait(0)
      fuzzyCompare(dot().y + dot().height, glyph.height, 0.01)
    }
  }
}
