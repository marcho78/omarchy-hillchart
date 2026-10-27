import QtQuick
import QtTest
import "../.."
import "../../HillModel.js" as Model

// HillView on its own: dots ride the curve under a real mouse drag, a click
// is only a click, the top pulls a dot in, and empty hill takes a new one.
// Run: QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml
Item {
  id: root
  width: 540
  height: 260

  ListModel { id: ids }

  property var byId: ({})
  property var moves: []
  property var adds: []
  property var toggles: []
  property var hides: []
  property var colors: []
  property string selected: ""
  property string hovered: ""

  HillView {
    id: hill
    x: 10
    y: 10
    width: 500
    height: 220
    model: ids
    byId: root.byId
    selectedId: root.selected
    hoveredId: root.hovered
    reduceMotion: true
    onSelectRequested: function(id) { root.selected = id }
    onHoverRequested: function(id) { root.hovered = id }
    onLabelToggleRequested: function(id) { root.toggles = root.toggles.concat([id]) }
    onLabelHideRequested: function(id) { root.hides = root.hides.concat([id]) }
    onColorRequested: function(id, x, y) { root.colors = root.colors.concat([{ id: id, x: x, y: y }]) }
    onAddRequested: function(p) { root.adds = root.adds.concat([p]) }
    onMoveRequested: function(id, p) {
      root.moves = root.moves.concat([{ id: id, p: p }])
      var next = Object.assign({}, root.byId)
      next[id] = Object.assign({}, next[id], { progress: p })
      root.byId = next
    }
  }

  TestCase {
    name: "HillView"
    when: windowShown

    function init() {
      ids.clear()
      root.byId = {}
      root.moves = []
      root.adds = []
      root.toggles = []
      root.hides = []
      root.colors = []
      root.selected = ""
      root.hovered = ""
    }

    function tag(id) { return findChild(hill, "tag-" + id) }
    function showing(id) { var t = tag(id); return !!t && t.visible && t.opacity > 0.5 }

    function put(id, progress, name, labelHidden) {
      var next = Object.assign({}, root.byId)
      next[id] = { id: id, name: name || id, progress: progress, color: 0, tint: "",
        labelHidden: labelHidden === true, updated: new Date().toISOString(), history: [] }
      root.byId = next
      ids.append({ pid: id })
    }

    function setHidden(id, hidden) {
      var next = Object.assign({}, root.byId)
      next[id] = Object.assign({}, next[id], { labelHidden: hidden })
      root.byId = next
    }

    function at(progress) { return Model.point(progress, hill.box) }

    function drag(fromX, fromY, toX, toY) {
      mousePress(hill, fromX, fromY)
      mouseMove(hill, fromX + 8, fromY, 0, Qt.LeftButton)
      mouseMove(hill, (fromX + toX) / 2, (fromY + toY) / 2, 0, Qt.LeftButton)
      mouseMove(hill, toX, toY, 0, Qt.LeftButton)
      mouseRelease(hill, toX, toY)
    }

    function test_drag_rides_the_hill() {
      put("a", 10)
      waitForRendering(hill)
      var from = at(10)
      var to = at(72)
      mousePress(hill, from.x, from.y)
      mouseMove(hill, from.x + 8, from.y, 0, Qt.LeftButton)
      // Height doesn't matter: the dot follows the pointer's x, on the curve.
      mouseMove(hill, to.x, from.y + 40, 0, Qt.LeftButton)
      compare(hill.dragId, "a")
      compare(hill.dragProgress, 72)
      mouseRelease(hill, to.x, from.y + 40)
      compare(root.moves.length, 1)
      compare(root.moves[0].id, "a")
      compare(root.moves[0].p, 72)
      compare(hill.dragId, "")
      compare(root.selected, "a")
    }

    function test_a_click_is_only_a_click() {
      put("a", 30)
      waitForRendering(hill)
      var p = at(30)
      mouseClick(hill, p.x, p.y)
      compare(root.selected, "a")
      compare(root.moves.length, 0)
      // Two pixels of wobble is still a click.
      mousePress(hill, p.x, p.y)
      mouseMove(hill, p.x + 2, p.y, 0, Qt.LeftButton)
      mouseRelease(hill, p.x + 2, p.y)
      compare(root.moves.length, 0)
    }

    function test_the_top_pulls_a_dot_in() {
      put("a", 20)
      waitForRendering(hill)
      var from = at(20)
      var nearTop = hill.box.x + hill.box.width * 0.515
      drag(from.x, from.y, nearTop, from.y)
      compare(root.moves.length, 1)
      compare(root.moves[0].p, 50)
    }

    function test_grabbed_off_center_the_dot_does_not_jump() {
      put("a", 40)
      waitForRendering(hill)
      var p = at(40)
      mousePress(hill, p.x + 6, p.y)
      mouseMove(hill, p.x + 6 + 4, p.y, 0, Qt.LeftButton)
      compare(hill.dragProgress, Model.progressAt(p.x + 4, hill.box))
      mouseRelease(hill, p.x + 10, p.y)
    }

    function test_drag_past_the_end_is_done() {
      put("a", 80)
      waitForRendering(hill)
      var from = at(80)
      drag(from.x, from.y, hill.width + 60, from.y)
      compare(root.moves[0].p, 100)
    }

    function test_a_tag_is_a_handle_too() {
      put("a", 60, "Billing")
      waitForRendering(hill)
      var t = hill.tagLayout["a"]
      verify(t && t.w > 0)
      var cx = t.x + t.w / 2
      var cy = t.y + t.h / 2
      drag(cx, cy, cx + hill.box.width * 0.2, cy)
      compare(root.moves.length, 1)
      verify(root.moves[0].p > 70 && root.moves[0].p < 90, "moved by the drag distance: " + root.moves[0].p)
    }

    function test_double_click_on_the_hill_adds_there() {
      waitForRendering(hill)
      var p = at(80)
      mouseDoubleClickSequence(hill, p.x, p.y - 30)
      compare(root.adds.length, 1)
      compare(root.adds[0], 80)
    }

    function test_double_click_on_a_dot_toggles_its_label() {
      put("a", 35)
      waitForRendering(hill)
      var p = at(35)
      mouseDoubleClickSequence(hill, p.x, p.y)
      compare(root.toggles, ["a"])
      compare(root.adds.length, 0)
      // Hidden, the dot is still the way back.
      setHidden("a", true)
      mouseDoubleClickSequence(hill, p.x, p.y)
      compare(root.toggles, ["a", "a"])
    }

    function test_double_click_on_a_label_hides_it() {
      put("a", 60, "Billing")
      waitForRendering(hill)
      var t = hill.tagLayout["a"]
      mouseDoubleClickSequence(hill, t.x + t.w / 2, t.y + t.h / 2)
      compare(root.hides, ["a"])
      compare(root.toggles.length, 0)
    }

    function test_right_click_on_a_dot_asks_for_its_color() {
      put("a", 30)
      waitForRendering(hill)
      var p = at(30)
      mouseClick(hill, p.x, p.y, Qt.RightButton)
      compare(root.colors.length, 1)
      compare(root.colors[0].id, "a")
      fuzzyCompare(root.colors[0].x, p.x, 1)
      compare(root.moves.length, 0, "a right-click never moves it")
      // A right-drag doesn't either.
      mousePress(hill, p.x, p.y, Qt.RightButton)
      mouseMove(hill, p.x + 80, p.y, 0, Qt.RightButton)
      mouseRelease(hill, p.x + 80, p.y, Qt.RightButton)
      compare(root.moves.length, 0)
      compare(hill.dragId, "")
    }

    function test_a_hidden_label_stays_hidden() {
      put("a", 20, "Auth", true)
      put("b", 70, "Billing")
      waitForRendering(hill)
      verify(!showing("a"), "hidden")
      verify(showing("b"), "the others show")
      compare(hill.tagLayout["a"], undefined, "no place on the hill")
      // Not on hover, not when picked.
      root.hovered = "a"
      verify(!showing("a"))
      root.selected = "a"
      verify(!showing("a"))
      // Pointing at another project dims nothing.
      root.hovered = "b"
      compare(tag("b").opacity, 1)
      setHidden("a", false)
      verify(showing("a"), "back when shown again")
    }

    function test_a_light_hill_shows_every_name() {
      // A real hill: one at the foot, two coming down, one nearly done.
      put("a", 8, "Uber Notebook Web")
      put("b", 63, "Uber TV Remote")
      put("c", 83, "Hill Chart Plugin")
      put("d", 97, "Nvdia Shield Port")
      waitForRendering(hill)
      verify(showing("a") && showing("b") && showing("c") && showing("d"))
      var rects = ["a", "b", "c", "d"].map(function(k) { return hill.tagLayout[k] })
      for (var i = 0; i < rects.length; i++)
        for (var j = i + 1; j < rects.length; j++) {
          var r = rects[i], q = rects[j]
          verify(!(r.x < q.x + q.w && q.x < r.x + r.w && r.y < q.y + q.h && q.y < r.y + r.h), "room for all four")
        }
    }

    function test_a_crowd_shows_every_label() {
      for (var i = 0; i < 14; i++) put("c" + i, 40 + i, "Project number " + i)
      waitForRendering(hill)
      for (var k = 0; k < 14; k++) verify(showing("c" + k), "c" + k + " shows; hiding is the user's call")
    }

    function test_a_hidden_label_does_not_catch_clicks() {
      put("a", 50, "Billing")
      waitForRendering(hill)
      var spot = hill.tagLayout["a"]
      verify(spot)
      setHidden("a", true)
      waitForRendering(hill)
      // The tag still sits where it was, faded out: a double-click there is
      // a double-click on the hill.
      mouseDoubleClickSequence(hill, spot.x + spot.w / 2, spot.y + spot.h / 2)
      compare(root.hides.length, 0)
      compare(root.adds.length, 1)
    }

    function test_tags_never_cover_each_other() {
      var names = ["Onboarding", "Auth rewrite", "Billing", "Docs site", "Mobile app", "Search", "Exports"]
      var spots = [5, 22, 30, 48, 50, 63, 64]
      for (var i = 0; i < names.length; i++) put("p" + i, spots[i], names[i])
      waitForRendering(hill)
      var rects = []
      for (var k in hill.tagLayout) rects.push(hill.tagLayout[k])
      compare(rects.length, names.length)
      for (var a = 0; a < rects.length; a++) {
        var r = rects[a]
        verify(r.x >= 0 && r.x + r.w <= hill.width, "inside: " + JSON.stringify(r))
        for (var b = a + 1; b < rects.length; b++) {
          var q = rects[b]
          verify(!(r.x < q.x + q.w && q.x < r.x + r.w && r.y < q.y + q.h && q.y < r.y + r.h),
            "overlap " + JSON.stringify(r) + " " + JSON.stringify(q))
        }
      }
    }

    function test_celebrating_does_not_throw() {
      put("a", 100)
      waitForRendering(hill)
      hill.celebrate("a", "top")
      hill.celebrate("a", "done")
      hill.celebrate("missing", "done")
      wait(20)
    }
  }
}
