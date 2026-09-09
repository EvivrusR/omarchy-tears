// Pure parsing and maths for the stats widget. Shared between QML (via
// `import "Stats.js" as Stats`) and node (tests/). No QML or DOM APIs here.

function parseSample(text) {
  var out = { cpu: null, mem: null, disk: null, batt: null }
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].trim().split(/\s+/)
    if (parts.length < 2) continue
    var nums = parts.slice(1).map(function(p) { return parseInt(String(p).replace("%", ""), 10) })
    switch (parts[0]) {
      case "cpu": {
        if (nums.length < 4 || nums.some(isNaN)) break
        var total = 0
        for (var j = 0; j < nums.length; j++) total += nums[j]
        var idle = nums[3] + (nums.length > 4 ? nums[4] : 0)
        out.cpu = { total: total, idle: idle }
        break
      }
      case "mem":
        if (nums.length >= 2 && !isNaN(nums[0]) && !isNaN(nums[1]))
          out.mem = { total: nums[0], avail: nums[1] }
        break
      case "disk":
        if (!isNaN(nums[0])) out.disk = nums[0]
        break
      case "batt":
        if (!isNaN(nums[0])) out.batt = { pct: nums[0], status: parts[2] || "" }
        break
    }
  }
  return out
}

function clampPct(v) {
  return Math.max(0, Math.min(100, Math.round(v)))
}

function cpuPercent(prev, cur) {
  if (!prev || !cur) return null
  var dTotal = cur.total - prev.total
  if (dTotal <= 0) return null
  var dIdle = cur.idle - prev.idle
  return clampPct(100 * (dTotal - dIdle) / dTotal)
}

function memPercent(mem) {
  if (!mem || !(mem.total > 0)) return null
  return clampPct(100 * (mem.total - mem.avail) / mem.total)
}

function batteryLabel(batt) {
  if (!batt) return ""
  var charging = batt.status === "Charging"
  return batt.pct + "%" + (charging ? "+" : "")
}

if (typeof module !== "undefined") module.exports = { parseSample, cpuPercent, memPercent, batteryLabel }
