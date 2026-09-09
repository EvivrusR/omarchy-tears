// Registry engine: defaults and validation driven by widgets/registry.json.
// Shared by Service.qml (via `import "Registry.js" as Registry`) and node tests.
// bin/desktop-widgets carries the Python twin; tests/fixtures/validate keeps them honest.

function fieldsFor(type, registry) {
  if (!registry || !registry.types || !registry.types[type]) return []
  var t = registry.types[type]
  var omit = t.omitCommon || []
  var common = (registry.common || []).filter(function(f) { return omit.indexOf(f.key) === -1 })
  return common.concat(t.fields || [])
}

// Indices of `list` in stacking order: ascending z, list order within equal z.
// Windows are created in this order, and the compositor stacks same-layer
// surfaces by creation, so lower z ends up further back.
function stackOrder(list) {
  var idx = []
  for (var i = 0; i < (list || []).length; i++) idx.push(i)
  idx.sort(function(a, b) {
    var za = Number(list[a] && list[a].z) || 0, zb = Number(list[b] && list[b].z) || 0
    return za !== zb ? za - zb : a - b
  })
  return idx
}

function clone(v) { return JSON.parse(JSON.stringify(v)) }

function applyDefaults(entry, registry) {
  var out = clone(entry || {})
  var fields = fieldsFor(String(out.type || ""), registry)
  for (var i = 0; i < fields.length; i++) {
    var f = fields[i]
    if (out[f.key] === undefined && f.default !== undefined) out[f.key] = clone(f.default)
  }
  return out
}

function isInt(v) { return typeof v === "number" && isFinite(v) && Math.floor(v) === v }

function checkField(f, value, push) {
  switch (f.type) {
    case "boolean":
      if (typeof value !== "boolean") push("error", f.key + " must be true or false")
      break
    case "integer":
      if (!isInt(value)) { push("error", f.key + " must be an integer"); return }
      if (f.min !== undefined && value < f.min) push("error", f.key + " must be at least " + f.min)
      if (f.max !== undefined && value > f.max) push("error", f.key + " must be at most " + f.max)
      break
    case "number":
      if (typeof value !== "number" || !isFinite(value)) { push("error", f.key + " must be a number"); return }
      if (f.min !== undefined && value < f.min) push("error", f.key + " must be at least " + f.min)
      if (f.max !== undefined && value > f.max) push("error", f.key + " must be at most " + f.max)
      break
    case "enum":
      if (typeof value !== "string" || (f.options || []).indexOf(value) === -1)
        push("error", f.key + " must be one of " + (f.options || []).join(", "))
      break
    case "multi-enum":
      if (!Array.isArray(value)) { push("error", f.key + " must be a list"); return }
      for (var i = 0; i < value.length; i++)
        if ((f.options || []).indexOf(value[i]) === -1) push("error", f.key + " has unknown option '" + value[i] + "'")
      break
    case "rows":
      if (!Array.isArray(value)) { push("error", f.key + " must be a list"); return }
      for (var r = 0; r < value.length; r++) {
        var row = value[r]
        if (!row || typeof row !== "object" || Array.isArray(row)) { push("error", f.key + "." + r + " must be an object"); continue }
        if ((f.options || []).indexOf(String(row.kind)) === -1) push("error", f.key + "." + r + " has unknown kind '" + row.kind + "'")
      }
      break
    case "string": case "path": case "command": case "color":
      if (typeof value !== "string") push("error", f.key + " must be a string")
      break
    default:
      break
  }
}

function validateEntry(entry, index, registry, messages) {
  function push(level, message, key) { messages.push({ level: level, widget: index, key: key || "", message: message }) }
  if (!entry || typeof entry !== "object" || Array.isArray(entry)) { push("error", "widget must be an object"); return }
  var type = entry.type
  if (type === undefined || type === null || type === "") { push("error", "missing type", "type"); return }
  if (typeof type !== "string" || !registry.types || !registry.types[type]) { push("error", "unknown type '" + type + "'", "type"); return }
  var fields = fieldsFor(type, registry)
  var known = {}
  for (var i = 0; i < fields.length; i++) {
    var f = fields[i]
    known[f.key] = true
    if (f.type === "type") continue
    if (entry[f.key] === undefined) continue
    checkField(f, entry[f.key], function(level, message) { push(level, message, f.key) })
  }
  for (var k in entry) if (!known[k]) push("warning", "unknown key '" + k + "'", k)
}

function validateConfig(parsed, registry) {
  var messages = []
  var list = Array.isArray(parsed) ? parsed
    : (parsed && typeof parsed === "object" && Array.isArray(parsed.widgets) ? parsed.widgets : null)
  if (!list) {
    messages.push({ level: "error", widget: -1, key: "", message: "config must be a list of widgets or an object with a widgets list" })
    return { widgets: null, messages: messages }
  }
  for (var i = 0; i < list.length; i++) validateEntry(list[i], i, registry, messages)
  return { widgets: list, messages: messages }
}

function hasErrors(messages, index) {
  for (var i = 0; i < messages.length; i++)
    if (messages[i].level === "error" && messages[i].widget === index) return true
  return false
}

if (typeof module !== "undefined") module.exports = { fieldsFor, applyDefaults, validateConfig, hasErrors, stackOrder }
