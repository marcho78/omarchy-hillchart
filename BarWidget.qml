pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "HillModel.js" as Model

// Hill Chart: where every project stands, from the bar.
//
// The bar shows a small hill with a dot per project. Clicking it opens the
// whole hill, where a dot is dragged along the curve as the work moves:
// uphill while you are still figuring out what the work is, over the top
// once nothing about it is unknown, downhill while you make it happen.
// A project is added by typing its name, or by double-clicking the hill
// right where it already stands. Nothing asks "are you sure": every change
// can be undone.
//
// Projects live in one JSON file (the dataFile setting), read and written
// only through bin/hillchart-files. Every bar on every monitor follows it, so
// a change made anywhere (another monitor, a script, an edit by hand) shows
// up everywhere, the dots gliding to their new spots.
Panel {
  id: root
  moduleName: "marcho78.hillchart"
  ipcTarget: "marcho78.hillchart"
  manageIpc: false

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // The catalog loads a moment after the widget does; text built before then
  // would show bare keys (and fill placeholders that aren't there).
  readonly property bool stringsReady: strings.t("title", "") !== ""

  function t(key) { return strings.t(key) }
  // A string with its placeholder filled, or "" while the catalog loads.
  function tArg(key, value) { return stringsReady ? strings.t(key).arg(value) : "" }
  function tCount(key, count) { return stringsReady ? strings.tn(key, count).arg(fmt(count)) : "" }
  function tn(key, count) { return strings.tn(key, count) }
  function fmt(n) { return Commons.I18n.formatNumber(n) }
  function formatPercent(p) { return fmt(p) + "%" }
  function phaseWord(p) {
    if (p >= 100) return t("phase.done")
    if (p === 50) return t("phase.top")
    return t(p > 50 ? "phase.downhill" : "phase.uphill")
  }
  function agoText(iso) {
    var a = Model.ago(iso, root.nowMs)
    if (a.unit === "now" || a.unit === "never") return t("ago." + a.unit)
    return tCount("ago." + a.unit, a.n)
  }

  readonly property var glyphs: ({
    rename: String.fromCodePoint(0xF03EB),
    done: String.fromCodePoint(0xF012C),
    reopen: String.fromCodePoint(0xF054C),
    remove: String.fromCodePoint(0xF01B4),
    add: String.fromCodePoint(0xF0415),
    clear: String.fromCodePoint(0xF003C),
    labelShown: String.fromCodePoint(0xF0208),
    labelHidden: String.fromCodePoint(0xF0209)
  })

  // ---- Settings

  readonly property string home: Quickshell.env("HOME")

  function expand(path) {
    var p = String(path || "")
    if (p === "~") return home
    if (p.indexOf("~/") === 0) return home + p.substring(1)
    return p
  }

  // Inside your home folder only: the file helper refuses anything else.
  readonly property string dataPath: expand(root.setting("dataFile", "")) || home + "/.local/share/hillchart/projects.json"
  readonly property int staleDays: Math.max(0, Math.floor(Number(root.setting("staleDays", 7)) || 0))

  // ---- State

  property var doc: Model.emptyDoc()
  property bool loaded: false
  property real nowMs: Date.now()
  property var swatches: Model.FALLBACK_PALETTE

  readonly property var projects: Model.active(doc)
  readonly property var orderedProjects: Model.ordered(projects)
  readonly property var counts: Model.counts(projects)
  readonly property int stalledCount: projects.filter(function(p) { return Model.isStale(p, root.nowMs, root.staleDays) }).length
  readonly property var byId: {
    var map = {}
    for (let i = 0; i < projects.length; i++) map[projects[i].id] = projects[i]
    return map
  }
  // Each project's row in the list: left to right as they stand on the hill.
  readonly property var rank: {
    var map = {}
    for (let i = 0; i < orderedProjects.length; i++) map[orderedProjects[i].id] = i
    return map
  }

  property string selectedId: ""
  property string hoveredId: ""
  property string renamingId: ""
  property int ghostProgress: -1

  property string toastText: ""
  property bool toastCanUndo: false

  // The project whose color picker is open, and where it opened, in the
  // panel's own coordinates.
  property string pickerId: ""
  property real pickerX: 0
  property real pickerY: 0

  function colorOf(project) { return Model.colorFor(project, swatches) }

  readonly property int hiddenLabels: projects.filter(function(p) { return p.labelHidden }).length

  readonly property string summaryText: {
    if (!stringsReady) return ""
    if (!projects.length) return t("summary.empty")
    var parts = [tCount("summary.projects", counts.total)]
    if (counts.uphill) parts.push(tArg("summary.uphill", fmt(counts.uphill)))
    if (counts.downhill) parts.push(tArg("summary.downhill", fmt(counts.downhill)))
    if (counts.done) parts.push(tArg("summary.done", fmt(counts.done)))
    return parts.join(" · ")
  }

  // ---- The file. Every read and write goes through bin/hillchart-files
  //      (see the README's Security section): no symbolic link is followed,
  //      no file is read past its cap, and every write is atomic and
  //      readable by you only.

  readonly property string filesHelper: decodeURIComponent(Qt.resolvedUrl("bin/hillchart-files").toString().replace(/^(file|qs):\/\//, ""))

  function filesCommand(args) {
    return ["/usr/bin/python3", "-I", "-S", root.filesHelper].concat(args)
  }

  property string lastWritten: ""
  // Why the projects file can't be used ("" while it can). Nothing is saved
  // while it's set, so a file Hill Chart refused to read is never written
  // over.
  property string fileProblem: ""
  property bool readAgain: false
  property string queuedWrite: ""
  property var undoStack: []
  property string lastChangeKey: ""
  property real lastChangeAt: 0

  // What we wrote comes back through the watcher; anything else is a change
  // made somewhere else, and an undo past it would quietly throw it away.
  function ingest(raw) {
    var text = String(raw || "")
    if (root.loaded && text === root.lastWritten) return
    var external = root.loaded
    root.doc = Model.parse(text, Date.now())
    root.loaded = true
    if (external) {
      root.undoStack = []
      root.lastChangeKey = ""
    }
  }

  // A read while a save is in flight would bring back the file as it was
  // before the save, so it waits for the saves to finish.
  function reload() {
    if (reader.running || writer.running || root.queuedWrite !== "") {
      root.readAgain = true
      return
    }
    reader.start(root.filesCommand(["read", root.dataPath]))
  }

  function write() {
    var text = Model.serialize(root.doc)
    root.lastWritten = text
    if (!root.loaded || root.fileProblem !== "") return
    if (writer.running) root.queuedWrite = text
    else writer.start(root.filesCommand(["write", root.dataPath]), text)
  }

  // Bars on the other monitors read the same file; after a save each reads
  // it again.
  function tellOtherBars() {
    if (!root.bar || typeof root.bar.moduleWidgets !== "function") return
    var widgets = root.bar.moduleWidgets(root.moduleName)
    for (let i = 0; i < widgets.length; i++) {
      let widget = widgets[i]
      if (widget && widget !== root && typeof widget.reload === "function") widget.reload()
    }
  }

  // Every change goes through here and onto the undo stack. Keyboard nudges
  // of one project in quick succession are one change, so holding an arrow
  // key and then undoing puts the dot back where it started.
  function commit(next, key) {
    if (!next || next === root.doc) return false
    var now = Date.now()
    var merge = !!key && key === root.lastChangeKey && now - root.lastChangeAt < 1500
    if (!merge) root.undoStack = root.undoStack.concat([root.doc]).slice(-50)
    root.lastChangeKey = key || ""
    root.lastChangeAt = now
    root.doc = next
    root.write()
    return true
  }

  function undo() {
    if (!root.undoStack.length) return
    root.doc = root.undoStack[root.undoStack.length - 1]
    root.undoStack = root.undoStack.slice(0, -1)
    root.lastChangeKey = ""
    root.write()
    if (root.renamingId && !root.byId[root.renamingId]) root.renamingId = ""
    root.showToast(t("toast.undone"), false)
  }

  Run {
    id: reader
    // The helper's most for a full file: every byte escaped to three.
    maxBytes: 3 * 1024 * 1024 + 64
    timeoutMs: 5000
    onFinished: function(code, output) {
      if (code === 0 || code === 3) {
        let text = ""
        try {
          text = code === 0 ? JSON.parse(output) : ""
          root.fileProblem = ""
          root.ingest(text)
        } catch (e) {
          root.fileProblem = "unreadable reply from the file helper"
        }
      } else {
        root.fileProblem = output
        console.warn("[hillchart] " + output)
      }
      if (root.readAgain) {
        root.readAgain = false
        root.reload()
      }
    }
  }

  Run {
    id: writer
    maxBytes: 16 * 1024
    timeoutMs: 10000
    onFinished: function(code, output) {
      if (code === 0) root.tellOtherBars()
      else root.showToast(root.tArg("toast.notSaved", output), false)
      if (root.queuedWrite !== "") {
        let next = root.queuedWrite
        root.queuedWrite = ""
        writer.start(root.filesCommand(["write", root.dataPath]), next)
      } else if (root.readAgain) {
        root.readAgain = false
        root.reload()
      }
    }
  }

  // Only word that the file changed, never a read of it: everything that is
  // read comes through the helper.
  FileView {
    path: root.dataPath
    preload: false
    watchChanges: true
    printErrors: false
    onFileChanged: root.reload()
  }

  onDataPathChanged: {
    root.loaded = false
    root.lastWritten = ""
    root.fileProblem = ""
    root.undoStack = []
    root.reload()
  }

  // Project colors follow the theme. The shell is told about a theme change
  // over IPC rather than by the file, so a new accent is the cue to read it
  // again.
  function readTheme() {
    if (!themeReader.running) themeReader.start(root.filesCommand(["theme"]))
  }

  Run {
    id: themeReader
    maxBytes: 3 * 64 * 1024 + 64
    timeoutMs: 5000
    onFinished: function(code, output) {
      var swatches = Model.FALLBACK_PALETTE
      if (code === 0) {
        try { swatches = Model.parsePalette(JSON.parse(output)) } catch (e) {}
      }
      root.swatches = swatches
    }
  }

  Connections {
    target: Commons.Color
    function onAccentChanged() { root.readTheme() }
    function onBackgroundChanged() { root.readTheme() }
  }

  Component.onCompleted: {
    root.reload()
    root.readTheme()
  }

  // "moved 3d ago" and stalled projects keep up with the clock.
  Timer {
    interval: root.opened ? 30000 : 600000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  // ---- One delegate per project for the hill, the bar and the list. Only
  //      comings and goings touch this model, so a project that moves keeps
  //      its dot and its row, and they animate to the new spot.

  ListModel { id: idModel }

  onProjectsChanged: syncIds()

  function syncIds() {
    var want = projects.map(function(p) { return p.id })
    for (let i = idModel.count - 1; i >= 0; i--) {
      if (want.indexOf(idModel.get(i).pid) < 0) idModel.remove(i)
    }
    var have = {}
    for (let j = 0; j < idModel.count; j++) have[idModel.get(j).pid] = true
    for (let k = 0; k < want.length; k++) {
      if (!have[want[k]]) idModel.append({ pid: want[k] })
    }
    if (root.selectedId && !root.byId[root.selectedId]) root.selectedId = ""
    if (root.hoveredId && !root.byId[root.hoveredId]) root.hoveredId = ""
  }

  // ---- Changes

  function addProject(name, progress) {
    var r = Model.addProject(root.doc, name, progress < 0 ? 0 : progress, Date.now(), root.swatches.length)
    if (!r.id) {
      if (Model.cleanName(name) && root.projects.length >= Model.MAX_PROJECTS) root.showToast(t("toast.full"), false)
      return ""
    }
    root.commit(r.doc)
    root.selectedId = r.id
    root.hideToast()
    Qt.callLater(function() { root.reveal(r.id) })
    return r.id
  }

  function moveProject(id, progress, key) {
    var before = root.byId[id]
    if (!before) return false
    var to = Model.clampProgress(progress)
    if (!root.commit(Model.moveProject(root.doc, id, to, Date.now()), key)) return false
    if (before.progress < 100 && to >= 100) root.celebrate(id, "done")
    else if (before.progress < 50 && to >= 50) root.celebrate(id, "top")
    // An older toast's Undo would now undo this move instead of what it names.
    else root.hideToast()
    return true
  }

  // Arrow keys step along a grid of 5% (1% with Shift), so a dot dragged to
  // 41% goes to 45% and then 50%, not 46% and 51%.
  function nudge(direction, fine) {
    var p = root.byId[root.selectedId]
    if (!p) {
      root.selectStep(1)
      return
    }
    var step = fine ? 1 : 5
    var to = direction > 0
      ? Math.floor(p.progress / step) * step + step
      : Math.ceil(p.progress / step) * step - step
    root.moveProject(p.id, to, "nudge:" + p.id)
  }

  // Done and back again: back to the last spot short of done.
  function toggleDone(id) {
    var p = root.byId[id]
    if (!p) return
    if (p.progress < 100) {
      root.moveProject(id, 100)
      return
    }
    var back = 90
    for (let i = p.history.length - 1; i >= 0; i--) {
      if (p.history[i].p < 100) { back = p.history[i].p; break }
    }
    root.moveProject(id, back)
  }

  function removeProject(id) {
    var p = root.byId[id]
    if (!p) return
    // The keyboard carries on from the neighbor, not from nothing.
    var order = root.orderedProjects
    var at = root.rank[id]
    var neighbor = order[at + 1] || order[at - 1] || null
    if (!root.commit(Model.removeProject(root.doc, id))) return
    if (root.renamingId === id) root.renamingId = ""
    if (root.selectedId === id) root.selectedId = neighbor ? neighbor.id : ""
    root.showToast(tArg("toast.removed", Model.elide(p.name, 40)), true)
  }

  function archiveDone() {
    var n = root.counts.done
    if (root.commit(Model.archiveDone(root.doc)))
      root.showToast(tCount("toast.cleared", n), true)
  }

  // ---- Labels: each project's can be hidden, or all of them at once.

  function setLabels(ids, hidden) {
    root.commit(Model.setLabelHidden(root.doc, ids, hidden))
  }

  function toggleLabel(id) {
    var p = root.byId[id]
    if (p) root.setLabels([id], !p.labelHidden)
  }

  // Shift+T: hide them all while any shows, else show them all.
  function toggleAllLabels() {
    root.setLabels(null, root.hiddenLabels < root.projects.length)
  }

  // ---- Colors: the one picked for a project replaces its automatic one.

  function openPicker(id, item, x, y) {
    var content = panel.loadedContent
    if (!root.byId[id] || !content) return
    var at = item.mapToItem(content, x, y)
    root.pickerX = at.x
    root.pickerY = at.y
    root.pickerId = id
  }

  function closePicker() { root.pickerId = "" }

  function pickColor(id, value) {
    if (root.byId[id]) root.commit(Model.setTint(root.doc, id, String(value)))
  }

  function startRename(id) {
    if (!root.byId[id]) return
    root.selectedId = id
    root.renamingId = id
    root.reveal(id)
  }

  function commitRename(id, name, refocus) {
    if (root.renamingId !== id) return
    root.renamingId = ""
    root.commit(Model.renameProject(root.doc, id, name))
    if (refocus) root.focusKeys()
  }

  function cancelRename() {
    root.renamingId = ""
    root.focusKeys()
  }

  function submitAdd(text) {
    var id = root.addProject(text, root.ghostProgress)
    if (!id) return false
    root.ghostProgress = -1
    return true
  }

  function startAddAt(progress) {
    root.ghostProgress = Model.clampProgress(progress)
    root.focusAdd()
  }

  function cancelAdd() {
    root.ghostProgress = -1
    if (panel.loadedContent) panel.loadedContent.clearAdd()
    root.focusKeys()
  }

  // ---- Selection and focus

  function select(id) {
    root.selectedId = id
    root.ghostProgress = -1
    root.focusKeys()
  }

  function selectStep(step) {
    var list = root.orderedProjects
    if (!list.length) return
    var at = root.rank[root.selectedId]
    var next = at === undefined ? (step > 0 ? 0 : list.length - 1) : Math.max(0, Math.min(list.length - 1, at + step))
    root.selectedId = list[next].id
    root.reveal(root.selectedId)
  }

  function reveal(id) { if (panel.loadedContent) panel.loadedContent.reveal(root.rank[id]) }
  function focusKeys() { if (panel.loadedContent) panel.loadedContent.focusKeys() }
  function focusAdd() { if (panel.loadedContent) panel.loadedContent.focusAdd() }

  function celebrate(id, kind) {
    if (root.opened && panel.loadedContent) panel.loadedContent.celebrate(id, kind)
    var p = root.byId[id]
    root.showToast(tArg(kind === "done" ? "toast.done" : "toast.top", Model.elide(p ? p.name : "", 40)), true)
  }

  function showToast(text, canUndo) {
    root.toastText = text
    root.toastCanUndo = !!canUndo
    toastTimer.restart()
  }

  function hideToast() {
    toastTimer.stop()
    root.toastText = ""
    root.toastCanUndo = false
  }

  Timer {
    id: toastTimer
    interval: 6000
    onTriggered: root.hideToast()
  }

  // Keys for the panel when no text field has them. Vim keys work as arrows;
  // Left and Right follow the reading direction.
  function handleKey(event) {
    if (root.renamingId !== "") return
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    if (ctrl) {
      if (event.key === Qt.Key_Z && !shift) { root.undo(); event.accepted = true }
      return
    }
    var key = Util.readingKey(event, true)
    var selected = root.selectedId
    var accepted = true
    switch (key) {
    case Qt.Key_Escape:
      if (root.pickerId !== "") root.closePicker()
      else root.close()
      break
    case Qt.Key_Tab: root.switchPanel(1); break
    case Qt.Key_Backtab: root.switchPanel(-1); break
    case Qt.Key_Left: root.nudge(-1, shift); break
    case Qt.Key_Right: root.nudge(1, shift); break
    case Qt.Key_Up: case Qt.Key_K: root.selectStep(-1); break
    case Qt.Key_Down: case Qt.Key_J: root.selectStep(1); break
    case Qt.Key_Home: if (selected) root.moveProject(selected, 0); break
    case Qt.Key_End: if (selected) root.moveProject(selected, 100); break
    case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_F2:
      if (selected) root.startRename(selected)
      else root.focusAdd()
      break
    case Qt.Key_Delete: case Qt.Key_Backspace: case Qt.Key_X:
      if (selected) root.removeProject(selected)
      break
    case Qt.Key_D: case Qt.Key_Space: if (selected) root.toggleDone(selected); break
    case Qt.Key_N: case Qt.Key_A: case Qt.Key_Plus: case Qt.Key_Insert: root.focusAdd(); break
    case Qt.Key_U: root.undo(); break
    case Qt.Key_T:
      if (shift) root.toggleAllLabels()
      else if (selected) root.toggleLabel(selected)
      break
    case Qt.Key_C: if (selected && panel.loadedContent) panel.loadedContent.pickerAtDot(selected); break
    default: accepted = false
    }
    if (accepted) event.accepted = true
  }

  // ---- Opening

  function open() {
    root.nowMs = Date.now()
    root.readTheme()
    root.reload()
    root.controller.show()
    // An empty hill has one thing to do: name the first project.
    if (!root.projects.length) Qt.callLater(root.focusAdd)
  }

  function close() {
    root.renamingId = ""
    root.pickerId = ""
    root.ghostProgress = -1
    root.hoveredId = ""
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function openToAdd() {
    if (!root.opened) root.open()
    Qt.callLater(root.focusAdd)
  }

  ShellIpc {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function peek(): void { root.showPeek() }
    function add(name: string): string { return root.addProject(name, 0) ? "ok" : "error" }
    function addAt(name: string, progress: int): string { return root.addProject(name, progress) ? "ok" : "error" }
    function move(project: string, progress: int): string {
      var p = Model.resolve(root.doc, project)
      if (!p) return "unknown"
      root.moveProject(p.id, progress)
      return "ok"
    }
    function remove(project: string): string {
      var p = Model.resolve(root.doc, project)
      if (!p) return "unknown"
      root.removeProject(p.id)
      return "ok"
    }
    function list(): string {
      var now = Date.now()
      return JSON.stringify(root.orderedProjects.map(function(p) {
        return { id: p.id, name: p.name, progress: p.progress, phase: Model.phase(p.progress),
          stale: Model.isStale(p, now, root.staleDays), updated: p.updated }
      }))
    }
  }

  // ---- The bar

  readonly property bool vertical: root.bar ? root.bar.vertical : false
  readonly property int miniHeight: vertical ? Style.space(11) : Math.round(Style.bar.iconCanvas * 0.9)
  readonly property int miniWidth: vertical
    ? Math.max(Style.space(16), (root.bar ? root.bar.barSize : Style.bar.sizeVertical) - Style.space(8))
    : Math.round(miniHeight * 2.9)
  // The open-panel mark under the widget spans the hill, not its padding.
  readonly property real openPanelIndicatorWidth: miniWidth
  readonly property real openPanelIndicatorHeight: miniHeight

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : root.miniWidth + Style.space(14)
    fixedHeight: root.vertical ? root.miniHeight + Style.space(14) : -1

    onPressed: function(b) {
      if (b === Qt.RightButton) root.openToAdd()
      else root.toggle()
    }

    MiniHill {
      anchors.centerIn: parent
      width: root.miniWidth
      height: root.miniHeight
      model: idModel
      byId: root.byId
      swatches: root.swatches
      lineColor: Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b, root.projects.length ? 0.55 : 0.4)
      ringColor: Commons.Color.bar.background
      dotSize: Math.max(4, Math.round(root.miniHeight * 0.45))
      lineWidth: Math.max(1, Style.spaceReal(1.25))
      reduceMotion: Style.reduceMotion
    }
  }

  // ---- Hover: a card with every project on a little hill of its own. It
  //      waits for the pointer to settle, so sweeping along the bar doesn't
  //      flash it, keeps out of the way of another open panel, and gives way
  //      to the full hill on a click.

  HoverCard {
    id: peek
    anchorItem: button
    bar: root.bar
    panel: root
  }

  Timer {
    id: peekDwell
    interval: 320
    onTriggered: {
      if (!button.tooltipHovered || root.opened) return
      if (root.bar && root.bar.activePopout) return
      peek.open = true
    }
  }

  Timer {
    id: peekLinger
    interval: 140
    onTriggered: if (!button.tooltipHovered) peek.open = false
  }

  Connections {
    target: button
    function onTooltipHoveredChanged() {
      if (button.tooltipHovered) {
        peekLinger.stop()
        peekDwell.restart()
      } else {
        peekDwell.stop()
        peekLinger.restart()
      }
    }
  }

  onOpenedChanged: {
    if (!root.opened) return
    peekDwell.stop()
    peekShown.stop()
    peek.open = false
  }

  // The same card from a key or a script, for a few seconds.
  function showPeek() {
    if (root.opened || (root.bar && root.bar.activePopout && root.bar.activePopout !== peek)) return
    peek.open = true
    peekShown.restart()
  }

  Timer {
    id: peekShown
    interval: 4000
    onTriggered: if (!button.tooltipHovered) peek.open = false
  }

  // ---- The panel

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: Item {
      id: body

      readonly property color fg: Commons.Color.popups.text
      readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.55)

      function focusKeys() { body.forceActiveFocus() }
      function focusAdd() { addField.forceActiveFocus() }
      function clearAdd() { addField.text = "" }
      function celebrate(id, kind) { hill.celebrate(id, kind) }
      function reveal(index) { list.reveal(index) }
      function pickerAtDot(id) {
        var p = root.byId[id]
        if (!p) return
        var pt = Model.point(p.progress, hill.box)
        root.openPicker(id, hill, pt.x, pt.y)
      }

      implicitHeight: column.implicitHeight
      focus: true
      Keys.onPressed: function(event) { if (!addField.activeFocus) root.handleKey(event) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        // ---- Heading: the title with its buttons, and the summary under
        //      them across the whole panel, where it has room to be read
        //      whole.
        Column {
          width: parent.width
          spacing: Style.space(3)

          Item {
            width: parent.width
            implicitHeight: Math.max(title.implicitHeight, actions.implicitHeight)

            Text {
              id: title
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.t("title")
              color: body.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Row {
              id: actions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Button {
                visible: root.counts.done > 0
                text: root.tCount("clearDone", root.counts.done)
                iconText: root.glyphs.clear
                tooltipText: root.t("clearDone.tip")
                fontSize: Style.font.bodySmall
                bordered: true
                onClicked: root.archiveDone()
              }

              Button {
                id: showAll
                visible: root.projects.length > 0
                enabled: root.hiddenLabels > 0
                opacity: showAll.enabled ? 1 : 0.4
                text: root.t("labels.showAll")
                iconText: root.glyphs.labelShown
                tooltipText: root.t("labels.showAllTip")
                fontSize: Style.font.bodySmall
                onClicked: root.setLabels(null, false)
              }

              Button {
                id: hideAll
                visible: root.projects.length > 0
                enabled: root.hiddenLabels < root.projects.length
                opacity: hideAll.enabled ? 1 : 0.4
                text: root.t("labels.hideAll")
                iconText: root.glyphs.labelHidden
                tooltipText: root.t("labels.hideAllTip")
                fontSize: Style.font.bodySmall
                onClicked: root.setLabels(null, true)
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            Text {
              id: summary
              width: Math.min(implicitWidth, parent.width - (stalledNote.visible ? stalledNote.implicitWidth + parent.spacing : 0))
              textFormat: Text.PlainText
              text: root.summaryText
              elide: Text.ElideRight
              color: body.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Text {
              id: stalledNote
              visible: root.stalledCount > 0
              textFormat: Text.PlainText
              text: "· " + root.tArg("summary.stalled", root.fmt(root.stalledCount))
              color: Commons.Color.urgent
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          // Why nothing is being saved, when the projects file was refused.
          Text {
            visible: root.fileProblem !== ""
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.tArg("file.problem", root.fileProblem)
            color: Commons.Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        // ---- The hill
        HillView {
          id: hill
          width: parent.width
          height: Style.space(220)
          model: idModel
          byId: root.byId
          swatches: root.swatches
          selectedId: root.selectedId
          hoveredId: root.hoveredId
          ghostProgress: root.ghostProgress
          nowMs: root.nowMs
          staleDays: root.staleDays
          live: root.opened
          foreground: body.fg
          background: Commons.Color.popups.background
          accent: Commons.Color.accent
          urgent: Commons.Color.urgent
          fontFamily: Style.font.family
          fontSize: Style.font.bodySmall
          captionSize: Style.font.caption
          unit: Style.spacing.scale
          cornerRadius: Style.cornerRadius
          reduceMotion: Style.reduceMotion
          uphillLabel: root.t("hill.uphill")
          downhillLabel: root.t("hill.downhill")
          bubbleFormat: root.stringsReady ? root.t("bubble") : "%1 · %2"
          host: root
          // The hill reads left to right in every language.
          LayoutMirroring.enabled: false
          LayoutMirroring.childrenInherit: true

          onSelectRequested: function(id) { root.selectedId = id; root.ghostProgress = -1 }
          onHoverRequested: function(id) { root.hoveredId = id }
          onMoveRequested: function(id, progress) { root.moveProject(id, progress) }
          onLabelToggleRequested: function(id) { root.toggleLabel(id) }
          onLabelHideRequested: function(id) { root.setLabels([id], true) }
          onColorRequested: function(id, x, y) { root.openPicker(id, hill, x, y) }
          onAddRequested: function(progress) { root.startAddAt(progress) }
          onClearRequested: { root.selectedId = ""; root.ghostProgress = -1 }
          onInteracted: if (root.renamingId === "") body.focusKeys()
        }

        // ---- The list, in hill order. Rows slide when the order changes.
        Item {
          id: listBox
          readonly property int rowHeight: Style.space(32)
          readonly property int rows: root.projects.length
          width: parent.width
          height: rows ? Math.min(rows, 6) * rowHeight : emptyNote.implicitHeight
          clip: true

          Behavior on height { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }

          Flickable {
            id: list
            anchors.fill: parent
            visible: listBox.rows > 0
            contentWidth: width
            contentHeight: listBox.rows * listBox.rowHeight
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            function reveal(index) {
              if (index === undefined || index < 0) return
              var top = index * listBox.rowHeight
              var bottom = top + listBox.rowHeight
              if (top < contentY) contentY = top
              else if (bottom > contentY + height) contentY = bottom - height
            }

            Repeater {
              model: idModel

              ProjectRow {
                panel: root
                width: list.width
                height: listBox.rowHeight
                y: (root.rank[pid] !== undefined ? root.rank[pid] : 0) * listBox.rowHeight
                Behavior on y { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
              }
            }
          }

          Column {
            id: emptyNote
            visible: listBox.rows === 0
            width: parent.width
            spacing: Style.space(4)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.t("empty.title")
              color: body.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              text: root.t("empty.body")
              color: body.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              lineHeight: 1.15
            }
          }
        }

        TextField {
          id: addField
          width: parent.width
          // Editable only while the panel shows: the panel stays loaded in
          // the shell after it closes, and an editable field has Qt read
          // every clipboard change even when nothing is pasted.
          readOnly: !root.opened
          maximumLength: Model.MAX_NAME
          foreground: body.fg
          placeholderText: root.glyphs.add + "  " + (root.ghostProgress >= 0
            ? root.tArg("add.placeholderAt", root.formatPercent(root.ghostProgress))
            : root.t("add.placeholder"))

          Keys.onEscapePressed: function(event) {
            // First Escape leaves the field (and drops a waiting spot);
            // the next one closes the panel.
            root.cancelAdd()
            event.accepted = true
          }
          Keys.onUpPressed: function(event) { root.focusKeys(); root.selectStep(-1); event.accepted = true }
          Keys.onDownPressed: function(event) { root.focusKeys(); root.selectStep(1); event.accepted = true }
          onAccepted: if (root.submitAdd(text)) text = ""
        }

        // ---- What the keys do, or what just happened.
        Item {
          width: parent.width
          implicitHeight: Math.max(hint.implicitHeight, toast.implicitHeight)

          Text {
            id: hint
            visible: root.toastText === ""
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.projects.length ? root.t("hint") : root.t("hint.empty")
            color: Qt.rgba(body.fg.r, body.fg.g, body.fg.b, 0.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Row {
            id: toast
            visible: root.toastText !== ""
            spacing: Style.space(12)

            Text {
              textFormat: Text.PlainText
              text: root.toastText
              color: body.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              visible: root.toastCanUndo && root.undoStack.length > 0
              textFormat: Text.PlainText
              text: root.t("toast.undo")
              color: Commons.Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              font.underline: undoMouse.containsMouse

              MouseArea {
                id: undoMouse
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.undo()
              }
            }
          }
        }
      }

      // ---- One project's color picker, over the rest of the panel. A
      //      press anywhere else puts it away.
      MouseArea {
        anchors.fill: parent
        z: 90
        visible: root.pickerId !== ""
        acceptedButtons: Qt.AllButtons
        onPressed: root.closePicker()
      }

      Rectangle {
        id: pickerCard
        readonly property int pad: Style.space(10)
        readonly property int gap: Style.space(16)

        visible: root.pickerId !== ""
        z: 91
        width: picker.implicitWidth + pad * 2
        height: picker.implicitHeight + pad * 2
        x: Math.max(0, Math.min(root.pickerX - width / 2, body.width - width))
        // Below the dot or swatch when it fits, above it when it doesn't.
        y: root.pickerY + gap + height <= body.height ? root.pickerY + gap : Math.max(0, root.pickerY - gap - height)
        radius: Style.cornerRadius
        color: Commons.Color.popups.background
        border.width: Math.max(1, Style.space(1))
        border.color: Commons.Color.popups.border

        // Presses on the card's own edge are not presses elsewhere.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        ColorPicker {
          id: picker
          x: pickerCard.pad
          y: pickerCard.pad
          color: root.pickerId !== "" ? root.colorOf(root.byId[root.pickerId]) : "#ffffff"
          outline: body.fg
          unit: Style.spacing.scale
          cornerRadius: Math.min(Style.cornerRadius, Style.space(4))
          onPicked: function(value) { root.pickColor(root.pickerId, value) }
        }
      }
    }
  }
}
