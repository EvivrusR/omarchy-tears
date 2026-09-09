// Strip // and /* */ comments and trailing commas from JSONC, leaving string
// contents untouched. Python twin: strip_jsonc in bin/desktop-widgets.
function strip(text) {
  var s = String(text || "")
  var out = ""
  var i = 0, n = s.length
  var inString = false
  while (i < n) {
    var c = s[i]
    if (inString) {
      out += c
      if (c === "\\" && i + 1 < n) { out += s[i + 1]; i += 2; continue }
      if (c === '"') inString = false
      i++
      continue
    }
    if (c === '"') { inString = true; out += c; i++; continue }
    if (c === "/" && s[i + 1] === "/") { while (i < n && s[i] !== "\n") i++; continue }
    if (c === "/" && s[i + 1] === "*") { i += 2; while (i < n && !(s[i] === "*" && s[i + 1] === "/")) i++; i += 2; continue }
    if (c === ",") {
      var k = i + 1
      while (true) {
        while (k < n && /\s/.test(s[k])) k++
        if (s[k] === "/" && s[k + 1] === "/") { while (k < n && s[k] !== "\n") k++ }
        else if (s[k] === "/" && s[k + 1] === "*") { k += 2; while (k < n && !(s[k] === "*" && s[k + 1] === "/")) k++; k += 2 }
        else break
      }
      if (s[k] === "}" || s[k] === "]") { i++; continue }
    }
    out += c
    i++
  }
  return out
}

if (typeof module !== "undefined") module.exports = { strip }
