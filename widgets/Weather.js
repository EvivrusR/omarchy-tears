// Weather effect engine: pure, node-tested. A field of falling/drifting glyphs
// plus a few multi-line cloud sprites, stepped by a timer in WeatherEffect.qml.

// Effect parameters per WMO group. density = particles per 100 cells;
// dy/dx = cells per tick; opacity = the preset's own alpha (× user).
var EFFECTS = {
  none:     { kind: "none", opacity: 0 },
  clear:    { kind: "twinkle", glyphs: [".", "·", "*", "✦"], density: 0.6, dy: 0, dx: 0, opacity: 0.12, sun: true },
  night:    { kind: "twinkle", glyphs: [".", "·", "*", "✦"], density: 1.2, dy: 0, dx: 0, opacity: 0.18 },
  partly:   { kind: "clouds", sprites: 4, dx: 0.5, opacity: 0.16 },
  overcast: { kind: "clouds", sprites: 9, dx: 0.3, opacity: 0.22 },
  fog:      { kind: "fog", glyphs: ["_", "-", "~", " "], density: 6, dy: 0, dx: 0.25, opacity: 0.3 },
  drizzle:  { kind: "fall", glyphs: ["'", "‚", "."], density: 2, dy: 1, dx: 0, opacity: 0.16 },
  rain:     { kind: "fall", glyphs: ["|", ":", "'"], density: 6, dy: 2, dx: 0, opacity: 0.26, slantWind: 20 },
  snow:     { kind: "fall", glyphs: ["*", "·", "❄", "✻"], density: 4, dy: 0.6, dx: 0, sway: true, opacity: 0.26 },
  storm:    { kind: "fall", glyphs: ["|", ":", "/"], density: 10, dy: 3, dx: 0, opacity: 0.3, flash: [8, 20], slantWind: 0 },
}

var CLOUD = ["  .--.  ", " (    ).", "(___.__)"]
var CLOUD_WIDE = ["    .-.    ", "  .(   ).  ", " (___(__)  "]
var SUN = ["   \\ | /   ", "  - (  ) - ", "   / | \\   "]

function effectFor(group, isDay, windKmh) {
  var key = group === "clear" ? (isDay ? "clear" : "night") : (EFFECTS[group] ? group : "none")
  var e = {}
  for (var k in EFFECTS[key]) e[k] = EFFECTS[key][k]
  e.name = key
  if (e.slantWind !== undefined && Number(windKmh) > e.slantWind) { e.dx = Number(windKmh) > 40 ? 1 : 0.5; e.glyphs = ["/", "/", "'"] }
  return e
}

function makeRand(seed) {
  var s = (Number(seed) || 1) >>> 0
  return function() { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296 }
}

function init(effect, cols, rows, densityMul, rand) {
  var st = { cols: cols, rows: rows, particles: [], sprites: [], tick: 0, flash: 0, nextFlash: 0 }
  var n = effect.kind === "fall" || effect.kind === "twinkle" || effect.kind === "fog" ? Math.round(cols * rows * (effect.density || 0) / 100 * (densityMul || 1)) : 0
  for (var i = 0; i < n; i++) st.particles.push({ c: rand() * cols, r: rand() * rows, g: Math.floor(rand() * effect.glyphs.length), s: 0.5 + rand() })
  if (effect.kind === "clouds") {
    var count = Math.max(1, Math.round((effect.sprites || 3) * (densityMul || 1)))
    for (var j = 0; j < count; j++) st.sprites.push({ c: rand() * cols, r: rand() * Math.max(1, rows - 4), wide: rand() < 0.4, s: 0.6 + rand() * 0.8 })
  }
  if (effect.flash) st.nextFlash = effect.flash[0] + Math.floor(rand() * (effect.flash[1] - effect.flash[0]))
  return st
}

function step(st, effect, rand, fps) {
  st.tick += 1
  var p, i
  if (effect.kind === "fall") {
    for (i = 0; i < st.particles.length; i++) {
      p = st.particles[i]
      p.r += effect.dy * p.s; p.c += effect.dx * p.s + (effect.sway ? (rand() - 0.5) * 0.6 : 0)
      if (p.r >= st.rows) { p.r = -1; p.c = rand() * st.cols; p.g = Math.floor(rand() * effect.glyphs.length) }
      if (p.c < 0) p.c += st.cols; if (p.c >= st.cols) p.c -= st.cols
    }
  } else if (effect.kind === "fog") {
    for (i = 0; i < st.particles.length; i++) { p = st.particles[i]; p.c += effect.dx * (Math.floor(p.r) % 2 ? 1 : -1) * p.s; if (p.c < 0) p.c += st.cols; if (p.c >= st.cols) p.c -= st.cols }
  } else if (effect.kind === "twinkle") {
    var flips = Math.max(1, Math.round(st.particles.length * 0.03))
    for (i = 0; i < flips; i++) { p = st.particles[Math.floor(rand() * st.particles.length)]; if (p) p.g = Math.floor(rand() * effect.glyphs.length) }
  } else if (effect.kind === "clouds") {
    for (i = 0; i < st.sprites.length; i++) { var sp = st.sprites[i]; sp.c += effect.dx * sp.s; if (sp.c > st.cols + 2) sp.c = -12 }
  }
  if (effect.flash) {
    if (st.flash > 0) st.flash -= 1
    else if (st.tick >= st.nextFlash) { st.flash = 2; st.nextFlash = st.tick + (effect.flash[0] + Math.floor(rand() * (effect.flash[1] - effect.flash[0]))) * (fps || 6) }
  }
  return st
}

// Rows of text for the particle field (sprites are drawn separately).
function render(st, effect) {
  var grid = [], r, c
  for (r = 0; r < st.rows; r++) { var row = []; for (c = 0; c < st.cols; c++) row.push(" "); grid.push(row) }
  for (var i = 0; i < st.particles.length; i++) {
    var p = st.particles[i], rr = Math.floor(p.r), cc = Math.floor(p.c)
    if (rr >= 0 && rr < st.rows && cc >= 0 && cc < st.cols) grid[rr][cc] = effect.glyphs[p.g % effect.glyphs.length]
  }
  var out = []
  for (r = 0; r < st.rows; r++) out.push(grid[r].join("").replace(/\s+$/, ""))
  return out
}

function sprites(st) {
  var out = []
  for (var i = 0; i < st.sprites.length; i++) out.push({ c: Math.round(st.sprites[i].c), r: Math.round(st.sprites[i].r), lines: st.sprites[i].wide ? CLOUD_WIDE : CLOUD })
  return out
}

if (typeof module !== "undefined") module.exports = { EFFECTS, effectFor, makeRand, init, step, render, sprites, SUN, CLOUD }
