// Pet rule engine. Pure; node-tested. The sprite sheet carries no logic
// (Hermes/petdex contract); everything below decides which row to show.

// ---- safe expression evaluator: numbers, true/false/null, dotted signal
// paths, comparison, && || !, parentheses. Unknown paths are null (falsy).
function tokenize(src) {
  var out = [], re = /\s*(>=|<=|==|!=|&&|\|\||[()!<>]|-?\d+(?:\.\d+)?|[A-Za-z_][\w.]*)/g, m, pos = 0
  while ((m = re.exec(src)) !== null) {
    if (m.index !== pos) throw new Error("bad token near '" + src.slice(pos, pos + 8) + "'")
    out.push(m[1]); pos = re.lastIndex
  }
  if (pos !== src.length && src.slice(pos).trim() !== "") throw new Error("bad token near '" + src.slice(pos, pos + 8) + "'")
  return out
}

function lookup(path, signals) {
  var parts = String(path).split("."), v = signals
  for (var i = 0; i < parts.length; i++) { if (v === null || v === undefined || typeof v !== "object") return null; v = v[parts[i]] }
  return v === undefined ? null : v
}

function evalExpr(src, signals) {
  var t = tokenize(String(src || "")), i = 0
  function peek() { return t[i] } function next() { return t[i++] }
  function atom() {
    var k = next()
    if (k === undefined) throw new Error("unexpected end")
    if (k === "(") { var v = orExpr(); if (next() !== ")") throw new Error("missing )"); return v }
    if (k === "!") return !truthy(atom())
    if (k === "true") return true; if (k === "false") return false; if (k === "null") return null
    if (/^-?\d/.test(k)) return Number(k)
    return lookup(k, signals)
  }
  function cmp() {
    var a = atom(), op = peek()
    if (op === ">=" || op === "<=" || op === ">" || op === "<" || op === "==" || op === "!=") {
      next(); var b = atom()
      if (a === null || b === null) return op === "!=" ? a !== b : (op === "==" ? a === b : false)
      switch (op) { case ">=": return a >= b; case "<=": return a <= b; case ">": return a > b; case "<": return a < b; case "==": return a == b; case "!=": return a != b }
    }
    return a
  }
  function andExpr() { var v = cmp(); while (peek() === "&&") { next(); var r = cmp(); v = truthy(v) && truthy(r) } return v }
  function orExpr() { var v = andExpr(); while (peek() === "||") { next(); var r = andExpr(); v = truthy(v) || truthy(r) } return v }
  var result = orExpr()
  if (i !== t.length) throw new Error("unexpected '" + t[i] + "'")
  return result
}
function truthy(v) { return v !== null && v !== undefined && v !== false && v !== 0 && v !== "" }

// ---- ready-made rule sets: what a pet can "watch". `when` = steady state,
// first match wins; `on` = edge (false → true) starts a timed beat.
var WATCH = {
  claude: [
    { kind: "on", if: "claude.resetInMin > 200", state: "jumping", beat: 2.2, say: "fresh session!" },
    { kind: "when", if: "claude.session >= 95", state: "failed", say: "session cap {claude.session}%" },
    { kind: "when", if: "claude.session >= 80", state: "waiting", say: "{claude.session}% used" },
    { kind: "when", if: "agents.active > 0", state: "running", say: "" },
    { kind: "when", if: "claude.session >= 50", state: "review", say: "{claude.session}%" },
  ],
  battery: [
    { kind: "on", if: "battery.full", state: "waving", beat: 2.2, say: "full!" },
    { kind: "when", if: "battery.discharging && battery.pct < 10", state: "failed", say: "{battery.pct}%!" },
    { kind: "when", if: "battery.discharging && battery.pct < 20", state: "waiting", say: "{battery.pct}%" },
    { kind: "when", if: "battery.charging", state: "running", say: "" },
  ],
  agents: [
    { kind: "on", if: "agents.active == 0", state: "waving", beat: 2.2, say: "all done" },
    { kind: "when", if: "agents.active > 0", state: "running", say: "{agents.active} working" },
  ],
  cpu: [
    { kind: "when", if: "cpu >= 95", state: "failed", say: "cpu {cpu}%" },
    { kind: "when", if: "cpu >= 60", state: "running", say: "cpu {cpu}%" },
    { kind: "when", if: "cpu >= 30", state: "review", say: "" },
  ],
  mem: [
    { kind: "when", if: "mem >= 95", state: "failed", say: "mem {mem}%" },
    { kind: "when", if: "mem >= 80", state: "waiting", say: "mem {mem}%" },
    { kind: "when", if: "mem >= 50", state: "review", say: "" },
  ],
  gpu: [
    { kind: "when", if: "gpu >= 95", state: "failed", say: "gpu {gpu}%" },
    { kind: "when", if: "gpu >= 60", state: "running", say: "gpu {gpu}%" },
    { kind: "when", if: "gpu >= 30", state: "review", say: "" },
    { kind: "when", if: "gpu == null", state: "idle", say: "no gpu here" },
  ],
}
var STATES = ["idle", "running", "waving", "jumping", "failed", "waiting", "review"]

function rulesFor(watch, custom) {
  if (String(watch) === "custom") return Array.isArray(custom) ? custom : []
  return WATCH[String(watch)] || []
}

function fill(text, signals) {
  return String(text || "").replace(/\{([\w.]+)\}/g, function(_, p) { var v = lookup(p, signals); return v === null ? "…" : (typeof v === "number" ? String(Math.round(v)) : String(v)) })
}

// One tick. prev = { signals, beatUntil, beatState, beatSay, edges: {ruleIndex: lastBool} }.
// Returns { state, say, beatUntil, beatState, beatSay, edges, signals }.
function step(rules, signals, prev, now) {
  var edges = {}, res = null, i, r, v
  var beatUntil = prev && prev.beatUntil > now ? prev.beatUntil : 0
  var beatState = beatUntil ? prev.beatState : null, beatSay = beatUntil ? prev.beatSay : ""
  for (i = 0; i < rules.length; i++) {
    r = rules[i]
    try { v = truthy(evalExpr(r.if, signals)) } catch (e) { v = false }
    if (String(r.kind) === "on") {
      var was = prev && prev.edges ? prev.edges[i] : undefined
      edges[i] = v
      if (v && was === false && !beatUntil) { beatUntil = now + Math.max(0.2, Number(r.beat) || 1.6) * 1000; beatState = String(r.state || "waving"); beatSay = fill(r.say, signals) }
    } else if (v && !res) res = { state: String(r.state || "idle"), say: fill(r.say, signals) }
  }
  var out = res || { state: "idle", say: "" }
  if (beatUntil) out = { state: beatState, say: beatSay }
  return { state: out.state, say: out.say, beatUntil: beatUntil, beatState: beatState, beatSay: beatSay, edges: edges, signals: signals }
}

// Hermes/petdex atlas: 192×208 cells, 8 columns; 9 rows (Codex) or 8 (legacy).
var FRAME_W = 192, FRAME_H = 208, COLS = 8, FRAMES = 6, LOOP_MS = 1100
var CODEX_ROWS = ["idle", "running-right", "running-left", "waving", "jumping", "failed", "waiting", "running", "review"]
var LEGACY_ROWS = ["idle", "waving", "running", "failed", "review", "jumping", "extra1", "extra2"]
function rowNames(sheetHeight) { return Math.round(sheetHeight / FRAME_H) === 8 ? LEGACY_ROWS : CODEX_ROWS }
function rowFor(state, sheetHeight, facingLeft) {
  var rows = rowNames(sheetHeight), s = String(state)
  var alias = { run: "running", wave: "waving", jump: "jumping" }
  s = alias[s] || s
  if (s === "running" && facingLeft && rows.indexOf("running-left") !== -1) s = "running-left"
  var i = rows.indexOf(s)
  if (i === -1 && s === "running") i = rows.indexOf("running-right")
  return i === -1 ? 0 : i
}
// Trailing blank cells (max alpha ≤ 8) are padding: count the real frames per row.
function trimCounts(maxAlphaPerCell, rows) {
  var out = []
  for (var r = 0; r < rows; r++) {
    var n = 0
    for (var c = 0; c < COLS && c < FRAMES + 2; c++) { var a = maxAlphaPerCell[r * COLS + c]; if (a !== undefined && a > 8) n = c + 1 }
    out.push(Math.max(1, n))
  }
  return out
}

if (typeof module !== "undefined") module.exports = { tokenize, evalExpr, lookup, WATCH, STATES, rulesFor, fill, step, rowFor, rowNames, trimCounts, FRAME_W, FRAME_H, COLS, FRAMES, LOOP_MS }
