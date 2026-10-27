.pragma library

// Everything about the hill chart that is not drawing: the document kept on
// disk, the shape of the hill, the words for where a project stands, and
// where the name tags go so they don't sit on each other. Kept apart from the
// QML so it can be tested on its own (tests/model.test.mjs).
//
// A project's progress runs 0..100 along the hill. The first half is uphill,
// figuring out what the work even is; 50 is the top, where the unknowns are
// gone; the second half is downhill, making it happen; 100 is done.

var VERSION = 1
var MAX_PROJECTS = 60
var MAX_NAME = 80
var MAX_HISTORY = 24
// Moves closer together than this are one session on the hill, so the trail
// keeps where a project was day to day rather than every nudge of a drag.
var COALESCE_MS = 30 * 60 * 1000
var DAY_MS = 24 * 60 * 60 * 1000

function clamp(v, lo, hi) {
  return Math.max(lo, Math.min(hi, v))
}

function clampProgress(value) {
  var n = Number(value)
  if (!isFinite(n)) return 0
  return Math.round(clamp(n, 0, 100))
}

// ---- The hill --------------------------------------------------------------

// A bell curve with flat feet, normalized so both feet touch the ground and
// the top reaches 1. Narrow enough that the climb reads as a climb.
var SIGMA = 0.17
var FOOT = Math.exp(-0.25 / (2 * SIGMA * SIGMA))

function height(t) {
  var x = clamp(Number(t) || 0, 0, 1) - 0.5
  return (Math.exp(-(x * x) / (2 * SIGMA * SIGMA)) - FOOT) / (1 - FOOT)
}

// Where progress (0..100) sits inside a box whose bottom edge is the ground.
function point(progress, box) {
  var t = clamp(Number(progress) || 0, 0, 100) / 100
  return { x: box.x + t * box.width, y: box.y + box.height - height(t) * box.height }
}

function outline(box, samples) {
  var n = Math.max(2, samples | 0)
  var points = []
  for (var i = 0; i <= n; i++) points.push(point(100 * i / n, box))
  return points
}

// The stretch of hill already climbed: from the foot up to `progress`,
// ending exactly there.
function outlineTo(box, samples, progress) {
  var end = clamp(Number(progress) || 0, 0, 100)
  var n = Math.max(2, samples | 0)
  var points = []
  for (var i = 0; i <= n && 100 * i / n < end; i++) points.push(point(100 * i / n, box))
  points.push(point(end, box))
  return points
}

// The progress under a horizontal position in the box. The top of the hill
// and both ends pull a dragged dot in, so "right at the top" and "done" are
// easy to land on and hard to miss by a pixel.
function progressAt(x, box, snap) {
  if (!(box.width > 0)) return 0
  var p = clamp((x - box.x) / box.width, 0, 1) * 100
  if (snap !== false) {
    if (Math.abs(p - 50) <= 2) return 50
    if (p <= 1) return 0
    if (p >= 99) return 100
  }
  return Math.round(p)
}

function phase(progress) {
  var p = clampProgress(progress)
  if (p >= 100) return "done"
  if (p >= 50) return "downhill"
  return "uphill"
}

// ---- The document ----------------------------------------------------------

function emptyDoc() {
  return { version: VERSION, projects: [] }
}

function cleanName(value) {
  return String(value === undefined || value === null ? "" : value)
    .replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, MAX_NAME)
    .trim()
}

function cleanId(value) {
  return String(value === undefined || value === null ? "" : value).replace(/[^A-Za-z0-9_-]/g, "").slice(0, 40)
}

function isoOrEmpty(value) {
  if (typeof value !== "string" || value.length > 40) return ""
  var t = Date.parse(value)
  return isFinite(t) ? new Date(t).toISOString() : ""
}

function newId(nowMs) {
  return "p" + Math.floor(nowMs).toString(36) + Math.floor(Math.random() * 1679616).toString(36)
}

function normalizeProject(raw, nowIso) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null
  var name = cleanName(raw.name)
  if (!name) return null
  var created = isoOrEmpty(raw.created) || nowIso
  var updated = isoOrEmpty(raw.updated) || created
  var history = []
  if (Array.isArray(raw.history)) {
    for (var i = 0; i < raw.history.length; i++) {
      var h = raw.history[i]
      if (!h || typeof h !== "object") continue
      var t = isoOrEmpty(h.t)
      if (!t) continue
      history.push({ t: t, p: clampProgress(h.p) })
    }
  }
  return {
    id: cleanId(raw.id),
    name: name,
    progress: clampProgress(raw.progress),
    color: clamp(Math.floor(Number(raw.color) || 0), 0, 63),
    tint: hexOrEmpty(raw.tint),
    labelHidden: raw.labelHidden === true,
    created: created,
    updated: updated,
    archived: raw.archived === true,
    history: history.slice(-MAX_HISTORY)
  }
}

// Anything that is not a document we wrote, or a hand edit of one, comes
// back as the empty hill rather than an error: the file is only ours.
function parse(raw, nowMs) {
  var data = null
  try { data = JSON.parse(String(raw || "")) } catch (e) { data = null }
  var doc = emptyDoc()
  if (!data || typeof data !== "object") return doc
  var list = Array.isArray(data) ? data : data.projects
  if (!Array.isArray(list)) return doc
  var nowIso = new Date(isFinite(nowMs) ? nowMs : Date.now()).toISOString()
  var seen = {}
  for (var i = 0; i < list.length && doc.projects.length < MAX_PROJECTS; i++) {
    var p = normalizeProject(list[i], nowIso)
    if (!p) continue
    if (!p.id || seen[p.id]) p.id = "p" + i + "x" + doc.projects.length
    seen[p.id] = true
    doc.projects.push(p)
  }
  return doc
}

function serialize(doc) {
  return JSON.stringify({ version: VERSION, projects: doc.projects }, null, 2) + "\n"
}

function copyDoc(doc) {
  return JSON.parse(JSON.stringify(doc))
}

function active(doc) {
  return doc.projects.filter(function(p) { return !p.archived })
}

function find(doc, id) {
  for (var i = 0; i < doc.projects.length; i++) if (doc.projects[i].id === id) return doc.projects[i]
  return null
}

// A name typed on the command line or over IPC: the id, else the one name
// that matches whole, else the one that starts with it (case ignored).
function resolve(doc, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return null
  var list = active(doc)
  var i
  for (i = 0; i < list.length; i++) if (list[i].id.toLowerCase() === q) return list[i]
  var whole = list.filter(function(p) { return p.name.toLowerCase() === q })
  if (whole.length === 1) return whole[0]
  var start = list.filter(function(p) { return p.name.toLowerCase().indexOf(q) === 0 })
  return start.length === 1 ? start[0] : null
}

// The least used color among projects still on the hill, lowest first, so
// a new project never looks like a neighbor when there is a choice.
function nextColor(doc, paletteSize) {
  var size = Math.max(1, paletteSize | 0)
  var counts = []
  for (var i = 0; i < size; i++) counts.push(0)
  active(doc).forEach(function(p) { counts[p.color % size] += 1 })
  var best = 0
  for (var j = 1; j < size; j++) if (counts[j] < counts[best]) best = j
  return best
}

function recordPosition(history, progress, nowMs) {
  var h = history.slice()
  var last = h.length ? h[h.length - 1] : null
  var nowIso = new Date(nowMs).toISOString()
  if (last && nowMs - Date.parse(last.t) < COALESCE_MS) h[h.length - 1] = { t: nowIso, p: progress }
  else h.push({ t: nowIso, p: progress })
  return h.slice(-MAX_HISTORY)
}

// Mutations copy the document, so the one before a change can sit on the
// undo stack untouched.
function addProject(doc, name, progress, nowMs, paletteSize) {
  var clean = cleanName(name)
  if (!clean || active(doc).length >= MAX_PROJECTS) return { doc: doc, id: "" }
  var next = copyDoc(doc)
  var p = clampProgress(progress)
  var nowIso = new Date(nowMs).toISOString()
  var id = newId(nowMs)
  while (find(next, id)) id = newId(nowMs + 1)
  next.projects.push({
    id: id,
    name: clean,
    progress: p,
    color: nextColor(doc, paletteSize),
    tint: "",
    labelHidden: false,
    created: nowIso,
    updated: nowIso,
    archived: false,
    history: [{ t: nowIso, p: p }]
  })
  return { doc: next, id: id }
}

function moveProject(doc, id, progress, nowMs) {
  var current = find(doc, id)
  var p = clampProgress(progress)
  if (!current || current.progress === p) return doc
  var next = copyDoc(doc)
  var project = find(next, id)
  project.progress = p
  project.updated = new Date(nowMs).toISOString()
  project.history = recordPosition(project.history, p, nowMs)
  return next
}

function renameProject(doc, id, name) {
  var clean = cleanName(name)
  var current = find(doc, id)
  if (!current || !clean || current.name === clean) return doc
  var next = copyDoc(doc)
  find(next, id).name = clean
  return next
}

// Hides or shows the labels of the given projects, or of every project on
// the hill when ids is null.
function setLabelHidden(doc, ids, hidden) {
  var want = hidden === true
  var pick = ids ? ids : active(doc).map(function(p) { return p.id })
  var changing = active(doc).some(function(p) { return pick.indexOf(p.id) >= 0 && p.labelHidden !== want })
  if (!changing) return doc
  var next = copyDoc(doc)
  next.projects.forEach(function(p) { if (!p.archived && pick.indexOf(p.id) >= 0) p.labelHidden = want })
  return next
}

// A color the user picked for a project, over the automatic one.
function setTint(doc, id, hex) {
  var tint = hexOrEmpty(hex)
  var current = find(doc, id)
  if (!current || !tint || current.tint === tint) return doc
  var next = copyDoc(doc)
  find(next, id).tint = tint
  return next
}

function removeProject(doc, id) {
  if (!find(doc, id)) return doc
  var next = copyDoc(doc)
  next.projects = next.projects.filter(function(p) { return p.id !== id })
  return next
}

// Finished work leaves the hill but stays in the file, history and all.
function archiveDone(doc) {
  var any = active(doc).some(function(p) { return p.progress >= 100 })
  if (!any) return doc
  var next = copyDoc(doc)
  next.projects.forEach(function(p) { if (p.progress >= 100) p.archived = true })
  return next
}

// ---- Reading the hill ------------------------------------------------------

// Left to right as they stand on the hill; ties keep the order they were added.
function ordered(projects) {
  return projects
    .map(function(p, i) { return { p: p, i: i } })
    .sort(function(a, b) { return a.p.progress - b.p.progress || a.i - b.i })
    .map(function(x) { return x.p })
}

function counts(projects) {
  var c = { total: projects.length, uphill: 0, downhill: 0, done: 0 }
  projects.forEach(function(p) { c[phase(p.progress)] += 1 })
  return c
}

function isStale(project, nowMs, staleDays) {
  var days = Number(staleDays)
  if (!(days > 0) || project.progress >= 100) return false
  var t = Date.parse(project.updated)
  return isFinite(t) && nowMs - t > days * DAY_MS
}

function daysSince(iso, nowMs) {
  var t = Date.parse(iso)
  return isFinite(t) ? Math.max(0, Math.floor((nowMs - t) / DAY_MS)) : 0
}

// Coarse elapsed time for "moved 3d ago": the unit names a translation key.
function ago(iso, nowMs) {
  var t = Date.parse(iso)
  if (!isFinite(t)) return { unit: "never", n: 0 }
  var minutes = Math.floor(Math.max(0, nowMs - t) / 60000)
  if (minutes < 1) return { unit: "now", n: 0 }
  if (minutes < 60) return { unit: "minutes", n: minutes }
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return { unit: "hours", n: hours }
  var days = Math.floor(hours / 24)
  if (days < 14) return { unit: "days", n: days }
  if (days < 60) return { unit: "weeks", n: Math.floor(days / 7) }
  return { unit: "months", n: Math.floor(days / 30) }
}

// Where a project has been: earlier stops on its way to where it is now,
// oldest first, without repeats of the same spot.
function trail(project, limit) {
  var out = []
  var seen = {}
  seen[project.progress] = true
  var h = project.history || []
  for (var i = h.length - 1; i >= 0 && out.length < (limit || 6); i--) {
    if (seen[h[i].p]) continue
    seen[h[i].p] = true
    out.unshift(h[i].p)
  }
  return out
}

function elide(text, max) {
  var s = String(text || "")
  return s.length > max ? s.slice(0, Math.max(1, max - 1)).replace(/\s+$/, "") + "…" : s
}

// ---- Colors ----------------------------------------------------------------

// Project colors come from the theme's colors.toml, in the order new projects
// take them. Themes name their colors; older ones only number them. Red goes
// last: on a status chart it reads as trouble.
var PALETTE_KEYS = [["blue", "color4"], ["green", "color2"], ["yellow", "color3"], ["magenta", "color5"], ["cyan", "color6"], ["orange", ""], ["red", "color1"]]
var FALLBACK_PALETTE = ["#7aa2f7", "#9ece6a", "#e0af68", "#bb9af7", "#7dcfff", "#ff9e64", "#f7768e"]

// Only #rrggbb gets in: the value goes straight into QML colors.
function hexOrEmpty(value) {
  var s = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  return /^#[0-9a-f]{6}$/.test(s) ? s : ""
}

// A project's color: the one picked for it, else its automatic one from the
// theme's palette.
function colorFor(project, swatches) {
  if (project && project.tint) return project.tint
  var list = swatches && swatches.length ? swatches : FALLBACK_PALETTE
  return list[(project ? project.color : 0) % list.length]
}

function parsePalette(raw) {
  var values = {}
  String(raw || "").split("\n").forEach(function(line) {
    var m = line.match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})\b/)
    if (m) values[m[1]] = m[2].toLowerCase()
  })
  var out = []
  PALETTE_KEYS.forEach(function(k) {
    var c = values[k[0]] || (k[1] ? values[k[1]] : "")
    if (c && out.indexOf(c) < 0) out.push(c)
  })
  return out.length >= 3 ? out : FALLBACK_PALETTE.slice()
}

// ---- Name tags -------------------------------------------------------------

function overlaps(a, b) {
  return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
}

// Places each name tag beside its dot. Uphill tags go to the left and
// downhill ones to the right, the side where the slope falls away from the
// dot, so a tag sits in the open air above the hill instead of across it.
// When that spot is taken by another tag or dot, or runs out of the box, the
// tag slides up or down just clear of what is in the way, the shortest slide
// first, and only then moves to the dot's other side. It never slides more
// than a row: further, and it would read as some other dot's name. A tag
// with nowhere clean to go still shows, beside its dot, over the others.
//
// items: [{ id, x, y, w, h, uphill, tag }] with (x, y) the dot's center;
// tag: false makes it a dot other tags keep clear of, with no tag of its own.
// bounds: { x, y, w, h }; gap: space between a dot and its tag;
// dot: the dot's size, which tags keep clear of; blocked: other rects
// ({ x, y, w, h }) no tag may cover, such as the hill's own labels.
// Returns { id: { x, y, w, h } } with (x, y) the tag's top left.
function layoutTags(items, bounds, gap, dot, blocked) {
  var r = (dot || 10) / 2
  var obstacles = items.map(function(it) {
    return { id: it.id, x: it.x - r, y: it.y - r, w: r * 2, h: r * 2 }
  })
  ;(blocked || []).forEach(function(b) { obstacles.push({ id: "", x: b.x, y: b.y, w: b.w, h: b.h }) })
  var placed = []
  var out = {}
  var order = items.filter(function(it) { return it.tag !== false }).sort(function(a, b) { return a.x - b.x })
  var top = bounds.y
  var bottom = bounds.y + bounds.h

  function fits(rect, id) {
    if (rect.x < bounds.x || rect.x + rect.w > bounds.x + bounds.w) return false
    for (var i = 0; i < placed.length; i++) if (overlaps(rect, placed[i])) return false
    for (var j = 0; j < obstacles.length; j++) {
      if (obstacles[j].id !== id && overlaps(rect, obstacles[j])) return false
    }
    return true
  }

  function rectAt(it, side, y) {
    var x = side === "left" ? it.x - r - gap - it.w : it.x + r + gap
    return { x: x, y: y, w: it.w, h: it.h }
  }

  function level(it) { return clamp(it.y - it.h / 2, top, bottom - it.h) }

  // Every height worth trying on one side of a dot: level with it, and just
  // above or below each thing in that tag's way, within a row of level.
  function heights(it, side) {
    var home = level(it)
    var row = it.h + 2
    var probe = rectAt(it, side, home)
    var ys = [home, home - row, home + row]
    placed.concat(obstacles).forEach(function(o) {
      if (o.id === it.id || !(probe.x < o.x + o.w && o.x < probe.x + probe.w)) return
      ys.push(o.y - it.h - 1, o.y + o.h + 1)
    })
    return ys.filter(function(y) { return Math.abs(y - home) <= row + 0.001 && y >= top && y + it.h <= bottom })
  }

  order.forEach(function(it) {
    var sides = it.uphill ? ["left", "right"] : ["right", "left"]
    var home = level(it)
    // Moving to the other side counts as half a row of sliding, so a small
    // nudge keeps a tag where its slope says it belongs.
    var tries = []
    sides.forEach(function(side, k) {
      heights(it, side).forEach(function(y) {
        tries.push({ side: side, y: y, cost: Math.abs(y - home) + k * (it.h + 2) / 2 })
      })
    })
    tries.sort(function(a, b) { return a.cost - b.cost })
    var chosen = null
    for (var i = 0; i < tries.length && !chosen; i++) {
      var rect = rectAt(it, tries[i].side, tries[i].y)
      if (fits(rect, it.id)) chosen = rect
    }
    if (!chosen) {
      chosen = rectAt(it, sides[0], home)
      if (chosen.x < bounds.x || chosen.x + chosen.w > bounds.x + bounds.w) chosen = rectAt(it, sides[1], home)
      chosen.x = clamp(chosen.x, bounds.x, bounds.x + bounds.w - chosen.w)
    }
    placed.push(chosen)
    out[it.id] = chosen
  })
  return out
}
