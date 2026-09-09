// Pure helpers for the editor panel. Node-tested; imported by Editor.qml.
function fieldsFor(type, registry) {
  if (!registry || !registry.types || !registry.types[type]) return []
  return (registry.common || []).concat(registry.types[type].fields || [])
}

function fieldDef(entry, key, registry) {
  var fields = fieldsFor(String(entry && entry.type || ""), registry)
  for (var i = 0; i < fields.length; i++) if (fields[i].key === key) return fields[i]
  return null
}

function same(a, b) { return JSON.stringify(a) === JSON.stringify(b) }

function newEntry(type, registry, corner) {
  return { type: type, corner: corner || "top-right" }
}

// Writes value into entry[key]; drops the key when it equals the registry default.
function setValue(entry, key, value, registry) {
  var f = fieldDef(entry, key, registry)
  if (f && f.default !== undefined && same(value, f.default)) delete entry[key]
  else entry[key] = value
  return entry
}

function valueOf(entry, key, registry) {
  if (entry && entry[key] !== undefined) return entry[key]
  var f = fieldDef(entry, key, registry)
  return f ? f.default : undefined
}

// Moves list[i] by dir (-1 up, +1 down); returns the new index.
function moveEntry(list, i, dir) {
  var j = i + dir
  if (j < 0 || j >= list.length) return i
  var tmp = list[i]; list[i] = list[j]; list[j] = tmp
  return j
}

function entryLabel(entry, registry) {
  if (!entry || !entry.type) return "(no type)"
  if (entry.title) return String(entry.title)
  var t = registry && registry.types ? registry.types[entry.type] : null
  return t && t.displayName ? t.displayName : String(entry.type)
}

function firstError(messages, index) {
  for (var i = 0; i < (messages || []).length; i++)
    if (messages[i].level === "error" && messages[i].widget === index) return messages[i].message
  return ""
}

function dirty(doc, saved) { return !same(doc, saved) }

if (typeof module !== "undefined") module.exports = { fieldsFor, fieldDef, newEntry, setValue, valueOf, moveEntry, entryLabel, firstError, dirty }
