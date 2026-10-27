import QtQuick
import QtTest
import "../.."

// ColorPicker: opens on a color, and a click or drag in the shades or the
// hue strip picks a color when the pointer lets go.
Item {
  width: 300
  height: 200

  ColorPicker {
    id: picker
    x: 10
    y: 10
  }

  SignalSpy {
    id: spy
    target: picker
    signalName: "picked"
  }

  TestCase {
    name: "ColorPicker"
    when: windowShown

    function init() {
      spy.clear()
      picker.color = "#ff0000"
    }

    function shades() { return findChild(picker, "shades") }
    function hues() { return findChild(picker, "hues") }

    function test_opens_on_its_color() {
      picker.color = "#00ff00"
      fuzzyCompare(picker.hue, 1 / 3, 0.01)
      fuzzyCompare(picker.sat, 1, 0.01)
      fuzzyCompare(picker.val, 1, 0.01)
    }

    function test_a_click_in_the_shades_picks() {
      var sq = shades()
      mouseClick(sq, sq.width / 2, sq.height / 2)
      compare(spy.count, 1)
      var c = spy.signalArguments[0][0]
      fuzzyCompare(c.hsvHue, 0, 0.01)
      fuzzyCompare(c.hsvSaturation, 0.5, 0.02)
      fuzzyCompare(c.hsvValue, 0.5, 0.02)
    }

    function test_a_drag_picks_where_it_lets_go() {
      var sq = shades()
      mousePress(sq, 5, 5)
      mouseMove(sq, sq.width * 0.25, sq.height * 0.75, 0, Qt.LeftButton)
      mouseMove(sq, sq.width * 0.9, sq.height * 0.1, 0, Qt.LeftButton)
      compare(spy.count, 0, "nothing picked until it lets go")
      mouseRelease(sq, sq.width * 0.9, sq.height * 0.1)
      compare(spy.count, 1)
      var c = spy.signalArguments[0][0]
      fuzzyCompare(c.hsvSaturation, 0.9, 0.02)
      fuzzyCompare(c.hsvValue, 0.9, 0.02)
    }

    function test_the_hue_strip_changes_the_hue() {
      var strip = hues()
      mouseClick(strip, strip.width / 2, strip.height * 2 / 3)
      compare(spy.count, 1)
      var c = spy.signalArguments[0][0]
      fuzzyCompare(c.hsvHue, 2 / 3, 0.01)
      fuzzyCompare(c.hsvSaturation, 1, 0.01)
    }

    function test_a_grey_keeps_the_hue_it_was_on() {
      picker.color = "#0000ff"
      var before = picker.hue
      picker.color = "#808080"
      compare(picker.hue, before)
      fuzzyCompare(picker.sat, 0, 0.01)
    }
  }
}
