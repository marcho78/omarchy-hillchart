// node tests/model.test.mjs
import { readFileSync } from "node:fs"
import assert from "node:assert/strict"

const src = readFileSync(new URL("../HillModel.js", import.meta.url), "utf8").replace(".pragma library", "")
const M = new Function(src + `; return { height, point, outline, outlineTo, progressAt, phase, parse, serialize, addProject,
  moveProject, renameProject, removeProject, archiveDone, ordered, counts, isStale, ago, trail,
  layoutTags, nextColor, resolve, cleanName, active, elide, parsePalette, FALLBACK_PALETTE, COALESCE_MS, MAX_NAME,
  MAX_PROJECTS, setLabelHidden, setTint, colorFor, hexOrEmpty }`)()

const NOW = Date.parse("2026-10-26T12:00:00Z")
const DAY = 24 * 60 * 60 * 1000
const near = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) < eps, `${a} ≈ ${b}`)

// ---- the hill: feet on the ground, top at 1, symmetric, rising then falling
near(M.height(0), 0)
near(M.height(1), 0)
near(M.height(0.5), 1)
near(M.height(0.3), M.height(0.7))
for (let i = 0; i < 10; i++) assert.ok(M.height((i + 1) / 20) > M.height(i / 20), "uphill rises")
for (let i = 10; i < 20; i++) assert.ok(M.height((i + 1) / 20) < M.height(i / 20), "downhill falls")
assert.ok(M.height(0.1) < 0.1, "the feet are flat")

const box = { x: 10, y: 20, width: 200, height: 100 }
assert.deepEqual(M.point(0, box), { x: 10, y: 120 })
assert.deepEqual(M.point(50, box), { x: 110, y: 20 })
assert.deepEqual(M.point(100, box), { x: 210, y: 120 })
assert.equal(M.outline(box, 40).length, 41)
assert.deepEqual(M.outlineTo(box, 40, 0), [M.point(0, box)], "nothing climbed yet")
const climbed = M.outlineTo(box, 40, 30)
assert.deepEqual(climbed[climbed.length - 1], M.point(30, box), "ends where the project stands")
assert.ok(climbed.every((p, i) => i === 0 || p.x > climbed[i - 1].x), "left to right, no repeats")
assert.equal(M.outlineTo(box, 40, 100).length, 41)

// dragging: x maps back to progress, the top and both ends pull a dot in
assert.equal(M.progressAt(110, box), 50)
assert.equal(M.progressAt(113, box), 50, "within 2% of the top snaps to it")
assert.equal(M.progressAt(116, box), 53)
assert.equal(M.progressAt(116, box, false), 53)
assert.equal(M.progressAt(-50, box), 0)
assert.equal(M.progressAt(500, box), 100)
assert.equal(M.progressAt(209, box), 100, "the last percent lands on done")
assert.equal(M.progressAt(11, box), 0)
assert.equal(M.progressAt(50, { x: 0, y: 0, width: 0, height: 10 }), 0, "an unlaid box is the foot")

assert.equal(M.phase(0), "uphill")
assert.equal(M.phase(49), "uphill")
assert.equal(M.phase(50), "downhill")
assert.equal(M.phase(99), "downhill")
assert.equal(M.phase(100), "done")

// ---- parsing: anything odd is an empty hill, never a throw
for (const raw of ["", "nope", "null", "42", "{}", '{"projects": 7}', "[[]]"])
  assert.deepEqual(M.parse(raw, NOW).projects, [], raw)

const parsed = M.parse(JSON.stringify({ projects: [
  { id: "a", name: "  Auth\n rewrite  ", progress: 141.7, color: 3, updated: "2026-10-20T00:00:00Z" },
  { id: "a", name: "Dup id", progress: -5 },
  { name: "" },
  { name: "<img src=x>", progress: "37" },
  "junk",
  { id: "../../etc", name: "Bad id", progress: 12, history: [{ t: "2026-10-01T00:00:00Z", p: 300 }, { t: "garbage", p: 1 }, 5] }
] }), NOW)
assert.equal(parsed.projects.length, 4)
assert.deepEqual(parsed.projects.map(p => p.name), ["Auth rewrite", "Dup id", "<img src=x>", "Bad id"])
assert.deepEqual(parsed.projects.map(p => p.progress), [100, 0, 37, 12])
assert.equal(new Set(parsed.projects.map(p => p.id)).size, 4, "ids are unique")
assert.equal(parsed.projects[3].id, "etc", "ids keep to a safe alphabet")
assert.deepEqual(parsed.projects[3].history, [{ t: "2026-10-01T00:00:00.000Z", p: 100 }])
assert.equal(parsed.projects[0].updated, "2026-10-20T00:00:00.000Z")
assert.equal(parsed.projects[1].created, new Date(NOW).toISOString(), "a missing date is now")
assert.equal(M.cleanName("x".repeat(500)).length, M.MAX_NAME)
assert.equal(M.cleanName("a\u2028b\tc"), "a b c")

// a bare array is read too, and the project cap holds
const many = Array.from({ length: 100 }, (_, i) => ({ id: "p" + i, name: "P" + i }))
assert.equal(M.parse(JSON.stringify(many), NOW).projects.length, M.MAX_PROJECTS)

// round trip
const back = M.parse(M.serialize(parsed), NOW)
assert.deepEqual(back, parsed)

// ---- mutations copy, never touch the document they were given
let doc = M.parse("", NOW)
let r = M.addProject(doc, "Onboarding", 0, NOW, 7)
assert.equal(doc.projects.length, 0, "the original is untouched")
doc = r.doc
const onboarding = r.id
assert.ok(onboarding)
assert.equal(M.addProject(doc, "   ", 0, NOW, 7).id, "", "no blank names")

r = M.addProject(doc, "Billing", 30, NOW + 1, 7)
doc = r.doc
const billing = r.id
assert.notEqual(billing, onboarding)
assert.deepEqual(doc.projects.map(p => p.color), [0, 1], "new projects take an unused color")
assert.deepEqual(doc.projects[1].history, [{ t: new Date(NOW + 1).toISOString(), p: 30 }])

const before = doc
doc = M.moveProject(doc, billing, 45, NOW + 1000)
assert.equal(M.moveProject(doc, billing, 45, NOW + 2000), doc, "a move to the same spot changes nothing")
assert.equal(before.projects[1].progress, 30)
assert.equal(doc.projects[1].progress, 45)
assert.equal(doc.projects[1].updated, new Date(NOW + 1000).toISOString())
assert.equal(doc.projects[1].history.length, 1, "moves inside one session are one stop")
doc = M.moveProject(doc, billing, 60, NOW + M.COALESCE_MS + 5000)
assert.deepEqual(doc.projects[1].history.map(h => h.p), [45, 60], "a later session is a new stop")
assert.deepEqual(M.trail(doc.projects[1]), [45])
assert.equal(M.moveProject(doc, "nope", 10, NOW), doc)

doc = M.renameProject(doc, billing, "  Billing v2 ")
assert.equal(doc.projects[1].name, "Billing v2")
assert.equal(M.renameProject(doc, billing, ""), doc, "renaming to nothing keeps the name")

assert.equal(M.resolve(doc, "bill").id, billing)
assert.equal(M.resolve(doc, "BILLING V2").id, billing)
assert.equal(M.resolve(doc, onboarding).id, onboarding)
assert.equal(M.resolve(doc, "zzz"), null)

doc = M.moveProject(doc, onboarding, 100, NOW + 3000)
assert.deepEqual(M.counts(M.active(doc)), { total: 2, uphill: 0, downhill: 1, done: 1 })
const archived = M.archiveDone(doc)
assert.deepEqual(M.active(archived).map(p => p.id), [billing])
assert.equal(archived.projects.length, 2, "archived projects stay in the file")
assert.equal(M.archiveDone(archived), archived, "nothing done, nothing changes")
assert.equal(M.nextColor(archived, 7), 0, "an archived project's color is free again")

doc = M.removeProject(doc, onboarding)
assert.deepEqual(doc.projects.map(p => p.id), [billing])

// ---- reading the hill
assert.deepEqual(M.ordered([{ progress: 50, n: 1 }, { progress: 10, n: 2 }, { progress: 50, n: 3 }]).map(p => p.n), [2, 1, 3])
const stale = { progress: 30, updated: new Date(NOW - 8 * DAY).toISOString() }
assert.equal(M.isStale(stale, NOW, 7), true)
assert.equal(M.isStale(stale, NOW, 10), false)
assert.equal(M.isStale(stale, NOW, 0), false, "0 days turns it off")
assert.equal(M.isStale({ ...stale, progress: 100 }, NOW, 7), false, "done work never stalls")

const iso = ms => new Date(NOW - ms).toISOString()
assert.deepEqual(M.ago(iso(10 * 1000), NOW), { unit: "now", n: 0 })
assert.deepEqual(M.ago(iso(5 * 60000), NOW), { unit: "minutes", n: 5 })
assert.deepEqual(M.ago(iso(3 * 3600000), NOW), { unit: "hours", n: 3 })
assert.deepEqual(M.ago(iso(3 * DAY), NOW), { unit: "days", n: 3 })
assert.deepEqual(M.ago(iso(20 * DAY), NOW), { unit: "weeks", n: 2 })
assert.deepEqual(M.ago(iso(90 * DAY), NOW), { unit: "months", n: 3 })
assert.deepEqual(M.ago("nope", NOW), { unit: "never", n: 0 })

// ---- name tags
const bounds = { x: 0, y: 0, w: 400, h: 200 }
let tags = M.layoutTags([
  { id: "up", x: 100, y: 120, w: 60, h: 16, uphill: true },
  { id: "down", x: 300, y: 120, w: 60, h: 16, uphill: false }
], bounds, 6, 12)
assert.ok(tags.up.x + tags.up.w <= 100 - 6, "uphill tags sit left of the dot")
assert.ok(tags.down.x >= 300 + 6, "downhill tags sit right of the dot")
assert.equal(tags.up.y, 112, "level with the dot")

// no room on the preferred side: the other side
tags = M.layoutTags([{ id: "edge", x: 10, y: 150, w: 80, h: 16, uphill: true }], bounds, 6, 12)
assert.ok(tags.edge.x > 10)

// a crowd: every tag still gets a spot inside the box, overlapping when
// there is no room (hiding labels is the user's call, not the layout's)
const overlap = (a, b) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
const crowd = Array.from({ length: 12 }, (_, i) => ({ id: "c" + i, x: 180 + i * 4, y: 60, w: 70, h: 16, uphill: i % 2 === 0 }))
tags = M.layoutTags(crowd, bounds, 6, 12)
assert.equal(Object.keys(tags).length, 12, "every tag gets a spot")
for (const t of Object.values(tags)) {
  assert.ok(t.x >= 0 && t.x + t.w <= 400 && t.y >= 0 && t.y + t.h <= 200, "inside the box")
  assert.equal(t.hidden, undefined, "the layout never hides a tag")
}

// spread out, nothing overlaps
const spread = Array.from({ length: 5 }, (_, i) => ({ id: "s" + i, x: 30 + i * 80, y: 100, w: 60, h: 16, uphill: false }))
const spreadTags = Object.values(M.layoutTags(spread, bounds, 6, 12))
for (let i = 0; i < spreadTags.length; i++)
  for (let j = i + 1; j < spreadTags.length; j++) assert.ok(!overlap(spreadTags[i], spreadTags[j]), "room for all")

// tags never wander more than a row from their dot
for (const t of Object.values(M.layoutTags(crowd, bounds, 6, 12)))
  assert.ok(Math.abs(t.y + t.h / 2 - 60) <= 16 + 2 + 0.001, "within a row of the dot")

// a hair's overlap is a nudge, not a lost name: a tag slides just clear of
// its neighbor into the gap below it instead of disappearing
tags = M.layoutTags([
  { id: "upper", x: 300, y: 150, w: 120, h: 21, uphill: false },
  { id: "lower", x: 380, y: 170.5, w: 120, h: 21, uphill: false }
], { x: 0, y: 0, w: 440, h: 200 }, 6, 18, [{ x: 200, y: 195, w: 200, h: 5 }])
assert.ok(!overlap(tags.upper, tags.lower), "the gap was found, nothing overlaps")
assert.ok(Math.abs(tags.lower.y + 10.5 - 170.5) < 4, "a nudge, not a jump")

// blocked rects (the hill's own labels) are never covered
const label = { x: 90, y: 150, w: 140, h: 14 }
tags = M.layoutTags([{ id: "foot", x: 100, y: 150, w: 60, h: 16, uphill: false }], bounds, 6, 12, [label])
assert.ok(!overlap(tags.foot, label), "the phase label stays readable")

// dots without tags: kept clear of, but no tag of their own
tags = M.layoutTags([
  { id: "named", x: 200, y: 100, w: 60, h: 16, uphill: false },
  { id: "dot", x: 220, y: 100, w: 60, h: 16, uphill: false, tag: false }
], bounds, 6, 12)
assert.deepEqual(Object.keys(tags), ["named"])
assert.ok(!overlap(tags.named, { x: 214, y: 94, w: 12, h: 12 }), "the other dot stays visible")

// ---- labels the user hides, colors the user picks
let pd = M.parse("", NOW)
let pr = M.addProject(pd, "Alpha", 10, NOW, 7); pd = pr.doc; const alpha = pr.id
pr = M.addProject(pd, "Beta", 60, NOW + 1, 7); pd = pr.doc; const beta = pr.id
assert.equal(pd.projects[0].labelHidden, false, "a new project shows its label")
assert.equal(pd.projects[0].tint, "", "and takes its automatic color")

let hid = M.setLabelHidden(pd, [alpha], true)
assert.deepEqual(hid.projects.map(p => p.labelHidden), [true, false], "one label hidden")
assert.equal(pd.projects[0].labelHidden, false, "the original is untouched")
assert.equal(M.setLabelHidden(hid, [alpha], true), hid, "hiding a hidden label changes nothing")
assert.deepEqual(M.setLabelHidden(hid, null, true).projects.map(p => p.labelHidden), [true, true], "hide all")
assert.deepEqual(M.setLabelHidden(hid, null, false).projects.map(p => p.labelHidden), [false, false], "show all")
assert.deepEqual(M.parse(M.serialize(hid), NOW).projects.map(p => p.labelHidden), [true, false], "saved")

assert.equal(M.hexOrEmpty("#A1B2C3"), "#a1b2c3")
for (const bad of ["red", "#fff", "#12345g", "#1234567", "javascript:alert(1)", "", null, 42])
  assert.equal(M.hexOrEmpty(bad), "", String(bad))
let tinted = M.setTint(pd, beta, "#FF8800")
assert.equal(tinted.projects[1].tint, "#ff8800")
assert.equal(pd.projects[1].tint, "", "the original is untouched")
assert.equal(M.setTint(tinted, beta, "#ff8800"), tinted, "same color, no change")
assert.equal(M.setTint(tinted, beta, "orange"), tinted, "only real colors get in")
assert.equal(M.parse(M.serialize(tinted), NOW).projects[1].tint, "#ff8800", "saved")
assert.equal(M.parse(JSON.stringify({ projects: [{ name: "x", tint: "url(evil)" }] }), NOW).projects[0].tint, "", "a bad color on disk is dropped")

const sw = ["#111111", "#222222", "#333333"]
assert.equal(M.colorFor(tinted.projects[1], sw), "#ff8800", "the picked color wins")
assert.equal(M.colorFor(tinted.projects[0], sw), "#111111", "else the automatic one")
assert.equal(M.colorFor({ color: 4, tint: "" }, sw), "#222222", "wrapping around the palette")
assert.equal(M.colorFor(null, []), M.FALLBACK_PALETTE[0])

// ---- words and colors
assert.equal(M.elide("Billing", 10), "Billing")
assert.equal(M.elide("Authentication rewrite", 10), "Authentic…")
assert.equal(M.elide("Auth rewrite now", 6), "Auth…", "no space before the ellipsis")

const named = `accent = "#7d82d9"\nred = "#ED5B5A"\nyellow = "#E9BB4F"\ngreen = "#92a593"\nblue = "#7d82d9"\nmagenta = "#c89dc1"`
assert.deepEqual(M.parsePalette(named), ["#7d82d9", "#92a593", "#e9bb4f", "#c89dc1", "#ed5b5a"])
const numbered = `color1 = "#aa0000"\ncolor2 = "#00aa00"\ncolor4 = "#0000aa"\ncolor3 = '#aaaa00'`
assert.deepEqual(M.parsePalette(numbered), ["#0000aa", "#00aa00", "#aaaa00", "#aa0000"])
assert.deepEqual(M.parsePalette(""), M.FALLBACK_PALETTE, "no theme, still colors")
assert.deepEqual(M.parsePalette(`blue = "#111111"\nred = "#111111"`), M.FALLBACK_PALETTE, "too few distinct colors")

console.log("model: ok")
