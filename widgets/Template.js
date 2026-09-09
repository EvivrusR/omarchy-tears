// Template widget helpers: parse a command's output, resolve {placeholders}
// with a small filter set, and compute bar fractions. Pure; node-tested.

function parseOutput(text) {
  var raw = String(text || "").replace(/\s+$/, "")
  var lines = raw === "" ? [] : raw.split("\n")
  var data = null
  try { data = JSON.parse(raw) } catch (e) { data = null }
  var out = data && typeof data === "object" && !Array.isArray(data) ? JSON.parse(JSON.stringify(data)) : {}
  out.output = raw
  out.lines = lines
  return out
}

function get(data, path) {
  if (data === null || data === undefined) return undefined
  var parts = String(path || "").split(".")
  var cur = data
  for (var i = 0; i < parts.length; i++) {
    if (cur === null || cur === undefined || typeof cur !== "object") return undefined
    cur = cur[parts[i]]
  }
  return cur
}

function human(n) {
  var v = Math.abs(n)
  var units = ["", "k", "M", "G", "T"]
  var u = 0
  while (v >= 1000 && u < units.length - 1) { v /= 1000; u++ }
  var s = v >= 100 || u === 0 ? Math.round(v).toString() : v.toFixed(1).replace(/\.0$/, "")
  return (n < 0 ? "-" : "") + s + units[u]
}

function secs(n) {
  var s = Math.max(0, Math.round(n))
  var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60
  if (h > 0) return h + "h " + (m < 10 ? "0" : "") + m + "m"
  if (m > 0) return m + "m " + (r < 10 ? "0" : "") + r + "s"
  return r + "s"
}

function applyFilter(value, name, arg) {
  var n = typeof value === "number" ? value : parseFloat(value)
  switch (name) {
    case "fixed": return isNaN(n) ? "—" : n.toFixed(Math.max(0, parseInt(arg || "0", 10) || 0))
    case "round": return isNaN(n) ? "—" : String(Math.round(n))
    case "int": return isNaN(n) ? "—" : String(Math.trunc(n))
    case "pct": return isNaN(n) ? "—" : Math.round(n * 100) + "%"
    case "upper": return String(value).toUpperCase()
    case "lower": return String(value).toLowerCase()
    case "human": return isNaN(n) ? "—" : human(n)
    case "secs": return isNaN(n) ? "—" : secs(n)
    case "default": return value === undefined || value === null || value === "" ? String(arg || "") : String(value)
    default: return String(value)
  }
}

var LB = "__DW_LBRACE__", RB = "__DW_RBRACE__"

function render(text, data) {
  var s = String(text === undefined || text === null ? "" : text)
  s = s.split("{{").join(LB).split("}}").join(RB)
  s = s.replace(/\{([^{}|]+)(?:\|([a-z]+)(?::([^{}]*))?)?\}/g, function(m, path, filter, arg) {
    var v = get(data, path.trim())
    if (filter === "default") return applyFilter(v, "default", arg)
    if (v === undefined || v === null) return "—"
    if (typeof v === "object") v = JSON.stringify(v)
    return filter ? applyFilter(v, filter, arg) : String(v)
  })
  return s.split(LB).join("{").split(RB).join("}")
}

function number(text, data, fallback) {
  var s = render(text, data)
  var n = parseFloat(s)
  return isNaN(n) ? fallback : n
}

function barFraction(row, data) {
  var v = number(row.value, data, NaN)
  if (isNaN(v)) return -1
  var min = number(row.min !== undefined ? row.min : "0", data, 0)
  var max = number(row.max !== undefined ? row.max : "100", data, 100)
  if (max === min) return -1
  var f = (v - min) / (max - min)
  return Math.max(0, Math.min(1, Math.round(f * 1000) / 1000))
}

if (typeof module !== "undefined") module.exports = { parseOutput, get, render, number, barFraction }
