// Time-keyed ring buffer for the monitor widgets. Pure; node-tested.
// A series is { windowSec, points: [{t, v}] }, oldest first, trimmed on push.
function create(windowSec) { return { windowSec: Math.max(1, Number(windowSec) || 300), points: [] } }

function push(s, t, v) {
  if (v === null || v === undefined || isNaN(Number(v))) return s
  s.points.push({ t: Number(t), v: Number(v) })
  var cutoff = Number(t) - s.windowSec
  while (s.points.length && s.points[0].t < cutoff) s.points.shift()
  return s
}

function latest(s) { return s.points.length ? s.points[s.points.length - 1].v : null }
function maxOf(s) { var m = 0; for (var i = 0; i < s.points.length; i++) if (s.points[i].v > m) m = s.points[i].v; return m }
function avgOf(s) { if (!s.points.length) return null; var a = 0; for (var i = 0; i < s.points.length; i++) a += s.points[i].v; return a / s.points.length }

// Normalised polyline for a sparkline: x 0..1 across the window (1 = now),
// y 0..1 (1 = `max`, or the series max when `max` is not a positive number).
function polyline(s, now, max) {
  var top = Number(max) > 0 ? Number(max) : maxOf(s)
  if (!(top > 0)) top = 1
  var out = []
  for (var i = 0; i < s.points.length; i++) {
    var p = s.points[i]
    out.push({ x: Math.max(0, Math.min(1, 1 - (now - p.t) / s.windowSec)), y: Math.max(0, Math.min(1, p.v / top)) })
  }
  return out
}

if (typeof module !== "undefined") module.exports = { create, push, latest, maxOf, avgOf, polyline }
