// Pure helpers for the monitor family (monitor, battery). Node-tested.
function netRate(prev, cur) {
  if (!prev || !cur || !prev.net || !cur.net || prev.net.iface !== cur.net.iface) return null
  var dt = Number(cur.t) - Number(prev.t)
  if (!(dt > 0)) return null
  var down = (cur.net.rx - prev.net.rx) / dt, up = (cur.net.tx - prev.net.tx) / dt
  if (down < 0 || up < 0) return null          // counter reset
  return { down: down, up: up }
}

function fmtRate(bytesPerSec) {
  if (bytesPerSec === null || bytesPerSec === undefined) return "…"
  var n = Number(bytesPerSec), units = ["B/s", "KB/s", "MB/s", "GB/s"], i = 0
  while (n >= 1000 && i < units.length - 1) { n /= 1000; i++ }
  return (i === 0 ? Math.round(n) : n < 10 ? n.toFixed(1) : Math.round(n)) + " " + units[i]
}

function fmtHours(h) {
  if (h === null || h === undefined || !(Number(h) >= 0)) return ""
  var m = Math.round(Number(h) * 60), hh = Math.floor(m / 60), mm = m % 60
  return hh > 0 ? hh + "h " + (mm < 10 ? "0" : "") + mm + "m" : mm + "m"
}

function fmtPct(v) { return v === null || v === undefined ? "…" : Math.round(Number(v)) + "%" }
function fmtTemp(v) { return v === null || v === undefined ? "…" : Math.round(Number(v)) + "°" }

// Which sample field feeds a monitor row, its unit, and the fixed scale (null = autoscale).
var ROWS = {
  cpu:      { label: "cpu",  max: 100, fmt: fmtPct },
  mem:      { label: "mem",  max: 100, fmt: fmtPct },
  gpu:      { label: "gpu",  max: 100, fmt: fmtPct },
  temp:     { label: "temp", max: null, fmt: fmtTemp },
  load:     { label: "load", max: null, fmt: function(v) { return v === null || v === undefined ? "…" : Number(v).toFixed(2) } },
  "net-down": { label: "↓",  max: null, fmt: fmtRate },
  "net-up":   { label: "↑",  max: null, fmt: fmtRate },
}

// Value for a row from a sample (+ the net rate computed by the caller).
function rowValue(key, sample, rate) {
  if (!sample) return null
  switch (key) {
    case "cpu": return sample.cpu ? sample.cpu.pct : null
    case "mem": return sample.mem ? sample.mem.pct : null
    case "gpu": return sample.gpu ? sample.gpu.pct : null
    case "temp": return sample.temp ? sample.temp.c : null
    case "load": return sample.load ? sample.load[0] : null
    case "net-down": return rate ? rate.down : null
    case "net-up": return rate ? rate.up : null
  }
  return null
}

// Battery glyph as text. style: "pixel" (segments), "outline" (nerd icons), "text".
function batteryGlyph(pct, charging, style) {
  var p = Math.max(0, Math.min(100, Number(pct) || 0))
  if (style === "text") return (charging ? "⚡" : "") + Math.round(p) + "%"
  if (style === "outline") {
    var icons = ["󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
    var chg = ["󰢟", "󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
    var i = Math.round(p / 10)
    return (charging ? chg : icons)[i]
  }
  var segs = 5, on = Math.round(p / 100 * segs)
  var body = ""
  for (var k = 0; k < segs; k++) body += k < on ? "█" : "░"
  return "[" + body + "]" + (charging ? "⚡" : "")
}

if (typeof module !== "undefined") module.exports = { netRate, fmtRate, fmtHours, fmtPct, fmtTemp, ROWS, rowValue, batteryGlyph }
