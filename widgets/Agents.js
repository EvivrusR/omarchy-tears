// Pure helpers for the agents widget: pick windows out of an
// omarchy-agent-usage-update record and format countdowns. Mirrors the
// label heuristics in the shell's omarchy.agents panel so both agree.

function isLong(text) {
  return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0
    || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0
}

function spanMs(label) {
  var text = String(label || "").toLowerCase()
  if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0) return 30 * 86400e3
  if (isLong(text)) return 7 * 86400e3
  var h = text.match(/(\d+)\s*-?\s*h(?:our)?\b/)
  if (h) return Number(h[1]) * 3600e3
  var m = text.match(/(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/)
  if (m) return Number(m[1]) * 60e3
  return 0
}

function windows(record) {
  if (!record || !Array.isArray(record.limits)) return []
  var out = []
  for (var i = 0; i < record.limits.length; i++) {
    var e = record.limits[i] || {}
    var pct = Number(e.percent)
    if (!(pct >= 0)) continue
    var label = String(e.label || "")
    var lower = label.toLowerCase()
    var kind = e.title ? "model" : (isLong(lower) ? "weekly" : (lower.indexOf("session") >= 0 || spanMs(label) > 0 ? "session" : "other"))
    out.push({ kind: kind, title: kind === "session" ? "Session" : kind === "weekly" ? "Weekly" : String(e.title || label),
               label: label, percent: pct, resetAt: String(e.resetsAt || "") })
  }
  return out
}

function firstOfKind(record, kind) {
  var list = windows(record)
  for (var i = 0; i < list.length; i++) if (list[i].kind === kind) return list[i]
  return null
}

function sessionWindow(record) { return firstOfKind(record, "session") }
function weeklyWindow(record) { return firstOfKind(record, "weekly") }

function formatDuration(ms) {
  if (!(ms > 0)) return ""
  var minutes = Math.floor(ms / 60000)
  var hours = Math.floor(minutes / 60)
  var days = Math.floor(hours / 24)
  if (days > 0) return days + "d " + (hours % 24) + "h"
  if (hours > 0) return hours + "h " + (minutes % 60) + "m"
  return Math.max(1, minutes) + "m"
}

// clockFn(Date) -> "HH:mm" is injected so QML can use Qt.formatTime.
function resetSummary(resetAt, nowMs, clockFn) {
  var iso = String(resetAt || "")
  if (!iso) return ""
  var at = Date.parse(iso)
  if (isNaN(at)) return ""
  var remaining = at - nowMs
  if (remaining <= 0) return "resetting…"
  return "ends in " + formatDuration(remaining) + " · " + clockFn(new Date(at))
}

if (typeof module !== "undefined") module.exports = { windows, sessionWindow, weeklyWindow, formatDuration, resetSummary }
