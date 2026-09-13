// Pet rule engine. Pure; node-tested. The sprite sheet carries no logic
// (Hermes/petdex contract); everything below decides which row to show.

// ---- safe expression evaluator: numbers, true/false/null, dotted signal
// paths, comparison, && || !, parentheses. Unknown paths are null (falsy).
function tokenize(src) {
  var out = [], re = /\s*(>=|<=|==|!=|&&|\|\||[()!<>]|-?\d+(?:\.\d+)?|'[^']*'|"[^"]*"|[A-Za-z_][\w.]*)/g, m, pos = 0
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
    if (k.charAt(0) === "'" || k.charAt(0) === '"') return k.slice(1, -1)
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
var LOOKS = ["idle", "running", "waving", "jumping", "failed", "waiting", "review"]
// A look the sheet lacks falls back along this chain, never silently to row 0.
var FALLBACK = { jumping: ["waving", "idle"], waiting: ["review", "idle"], failed: ["waiting", "idle"], running: ["idle"], review: ["idle"], waving: ["idle"], idle: [] }
function rowNames(sheetHeight) {
  var n = Math.round(sheetHeight / FRAME_H)
  if (n === 8) return LEGACY_ROWS
  var rows = CODEX_ROWS.slice()
  for (var r = 10; r <= n; r++) rows.push("extra" + r)      // 10-/11-row exports: rows past 9 are extras
  return rows
}
function rowIndex(name, rows, present) {
  var i = rows.indexOf(name)
  return i === -1 || (present && present[i] === false) ? -1 : i
}
function rowFor(state, sheetHeight, facingLeft, present) {
  var rows = rowNames(sheetHeight), s = String(state)
  var alias = { run: "running", wave: "waving", jump: "jumping" }
  s = alias[s] || s
  var chain = [s].concat(FALLBACK[s] || ["idle"])
  for (var k = 0; k < chain.length; k++) {
    var want = chain[k], i = -1
    if (want === "running") {
      if (facingLeft) i = rowIndex("running-left", rows, present)
      if (i === -1) i = rowIndex("running", rows, present)
      if (i === -1) i = rowIndex("running-right", rows, present)
    } else i = rowIndex(want, rows, present)
    if (i !== -1) return i
  }
  return 0
}
// Which look is actually shown for `state` given the present look names.
function resolveLook(state, presentNames) {
  var s = String(state), chain = [s].concat(FALLBACK[s] || ["idle"])
  for (var k = 0; k < chain.length; k++) if (!presentNames || presentNames.indexOf(chain[k]) !== -1) return chain[k]
  return "idle"
}
// Trailing blank cells (max alpha ≤ 8) are padding: count the real frames per row.
function trimInfo(maxAlphaPerCell, rows) {
  var counts = [], present = []
  for (var r = 0; r < rows; r++) {
    var n = 0
    for (var c = 0; c < COLS && c < FRAMES + 2; c++) { var a = maxAlphaPerCell[r * COLS + c]; if (a !== undefined && a > 8) n = c + 1 }
    counts.push(Math.max(1, n)); present.push(n > 0)
  }
  return { counts: counts, present: present }
}
function trimCounts(maxAlphaPerCell, rows) { return trimInfo(maxAlphaPerCell, rows).counts }
// User-facing looks: one per row, except running-right/running-left/running
// (Codex sheets) collapse into a single `running` look. `info` (from
// trimInfo) supplies per-row frame counts and presence; a row past what
// `info` covers, or no `info` at all, counts as present.
function looks(sheetHeight, info) {
  var rows = rowNames(sheetHeight)
  var counts = (info && info.counts) || [], present = (info && info.present) || []
  function isPresent(row) { return row < present.length ? !!present[row] : true }
  function frameCount(row) { return counts[row] || FRAMES }
  if (rows === LEGACY_ROWS) {
    var legacy = []
    for (var r = 0; r < rows.length; r++) legacy.push({ name: rows[r], row: r, frames: frameCount(r), present: isPresent(r) })
    return legacy
  }
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var name = rows[i]
    if (name === "running" || name === "running-right" || name === "running-left") continue
    out.push({ name: name, row: i, frames: frameCount(i), present: isPresent(i) })
  }
  var runOrder = [7, 1, 2], runRow = -1               // running, running-right, running-left
  for (var k = 0; k < runOrder.length; k++) { if (isPresent(runOrder[k])) { runRow = runOrder[k]; break } }
  var running = runRow === -1
    ? { name: "running", row: 7, frames: FRAMES, present: false }
    : { name: "running", row: runRow, frames: frameCount(runRow), present: true }
  out.splice(1, 0, running)
  return out
}

// Layers: normalise a config row into what the widget draws.
function layerSpec(row) {
  if (!row || typeof row !== "object") return null
  var kind = String(row.kind || (row.sheet ? "sheet" : "image"))
  var src = String(kind === "sheet" ? (row.sheet || "") : (row.image || ""))
  if (!src) return null
  return { kind: kind, source: src, front: String(row.z || "front") !== "back", x: Number(row.x) || 0, y: Number(row.y) || 0,
           scale: Number(row.scale) > 0 ? Number(row.scale) : 1, follow: String(row.follow || "idle") }
}
function layerSpecs(rows) {
  var out = []
  for (var i = 0; i < (rows || []).length; i++) { var l = layerSpec(rows[i]); if (l) out.push(l) }
  return out
}
// Union of the body cell and every layer, in screen px. `sizes` maps a layer
// index to its natural {w, h} (props) once loaded; unknown sizes count as 0.
function bounds(layers, bodyW, bodyH, cellScale, sizes) {
  var minX = 0, minY = 0, maxX = bodyW, maxY = bodyH
  for (var i = 0; i < (layers || []).length; i++) {
    var l = layers[i], x = l.x * cellScale, y = l.y * cellScale, w, h
    if (l.kind === "sheet") { w = bodyW; h = bodyH }
    else { var sz = sizes && sizes[i] ? sizes[i] : { w: 0, h: 0 }; w = sz.w * cellScale * l.scale; h = sz.h * cellScale * l.scale }
    if (x < minX) minX = x; if (y < minY) minY = y
    if (x + w > maxX) maxX = x + w; if (y + h > maxY) maxY = y + h
  }
  return { x: minX, y: minY, w: Math.ceil(maxX - minX), h: Math.ceil(maxY - minY) }
}

// What a pet publishes for the others: pets.<name>.{state, say, watch}.
function petName(config) {
  var n = String(config.name || "").trim()
  if (n) return n.toLowerCase().replace(/[^a-z0-9_]+/g, "_")
  var parts = String(config.sheet || "").replace(/\/+$/, "").split("/")
  return (parts.length >= 2 ? parts[parts.length - 2] : parts[parts.length - 1] || "pet").toLowerCase().replace(/[^a-z0-9_]+/g, "_")
}

// Published names for a whole widget list: non-pets and disabled pets are
// null and consume no name (a disabled `teto` must not bump the enabled one
// to `teto_2`); a repeated enabled name becomes name_2, name_3…
function uniqueNames(configs) {
  var seen = {}, out = []
  for (var i = 0; i < (configs || []).length; i++) {
    var c = configs[i]
    if (!c || String(c.type) !== "pet" || c.enabled === false) { out.push(null); continue }
    var base = petName(c), n = (seen[base] || 0) + 1
    seen[base] = n
    out.push(n === 1 ? base : base + "_" + n)
  }
  return out
}

if (typeof module !== "undefined") module.exports = { layerSpec, layerSpecs, petName, uniqueNames, bounds, tokenize, evalExpr, lookup, WATCH, STATES, rulesFor, fill, step, rowFor, rowNames, trimCounts, LOOKS, FALLBACK, trimInfo, looks, resolveLook, FRAME_W, FRAME_H, COLS, FRAMES, LOOP_MS }
