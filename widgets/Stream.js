// What the shared sampler (bin/dw-stream) must do for a layout. Pure; node-tested.
// Monitors, batteries and pets read one stream from the service instead of each
// starting a Python process per tick; the stream runs at the fastest interval any
// of them asks for, and each widget keeps its own pace by skipping samples.
function positiveInt(v, fallback, min) { var n = parseInt(v); return Math.max(min, isNaN(n) || n <= 0 ? fallback : n) }

function plan(widgets) {
  var interval = 0, ifaces = [], commands = [], signals = false, seenIface = {}, seenKey = {}
  function want(sec) { if (!interval || sec < interval) interval = sec }
  for (var i = 0; i < (widgets || []).length; i++) {
    var w = widgets[i]
    if (!w || w.enabled === false) continue
    var type = String(w.type)
    if (type === "monitor") {
      want(positiveInt(w.intervalSec, 10, 2))
      var iface = String(w.iface || "")
      if (iface && !seenIface[iface]) { seenIface[iface] = true; ifaces.push(iface) }
    } else if (type === "battery") {
      want(positiveInt(w.intervalSec, 30, 5))
    } else if (type === "pet") {
      want(positiveInt(w.intervalSec, 5, 2))
      signals = true
      var rows = w.signals && typeof w.signals.length === "number" ? w.signals : []
      for (var r = 0; r < rows.length; r++) {
        var s = rows[r]
        if (s && s.key && s.command && !seenKey[s.key]) { seenKey[s.key] = true; commands.push(String(s.key) + "=" + String(s.command)) }
      }
    }
  }
  return { interval: interval, ifaces: ifaces, commands: commands, signals: signals }
}

// argv for bin/dw-stream (after the executable); [] when nothing needs sampling.
function args(p) {
  if (!p || !p.interval) return []
  var out = ["--interval", String(p.interval)]
  for (var i = 0; i < p.ifaces.length; i++) out.push("--iface", p.ifaces[i])
  if (p.signals) out.push("--signals")
  for (var c = 0; c < p.commands.length; c++) out.push("--command", p.commands[c])
  return out
}

// Whether a widget sampling every `intervalSec` should take a sample stamped `t`,
// having last taken one at `lastT`. Half a stream interval of slack, so a 10 s
// monitor on a 5 s stream takes every second sample rather than every third.
function due(lastT, t, intervalSec, streamSec) {
  if (!(lastT > 0)) return true
  return t - lastT >= Number(intervalSec) - Number(streamSec || 0) / 2
}

if (typeof module !== "undefined") module.exports = { plan, args, due }
