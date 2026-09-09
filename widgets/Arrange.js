// Placement maths for arrange mode. Screen-space logical pixels; corners as
// in the registry. Shared by the overlay (QML) and node tests.
function rectFor(corner, x, y, w, h, sw, sh) {
  var c = String(corner)
  var right = c.indexOf("right") !== -1, center = c.indexOf("center") !== -1
  var bottom = c.indexOf("bottom") === 0
  return { x: center ? Math.round((sw - w) / 2) : right ? sw - x - w : x, y: bottom ? sh - y - h : y, w: w, h: h }
}

function placeFor(rect, sw, sh) {
  var cx = rect.x + rect.w / 2, cy = rect.y + rect.h / 2
  var right = cx > sw / 2, bottom = cy > sh / 2
  var corner = (bottom ? "bottom" : "top") + "-" + (right ? "right" : "left")
  var x = right ? sw - rect.x - rect.w : rect.x
  var y = bottom ? sh - rect.y - rect.h : rect.y
  return { corner: corner, x: Math.max(0, Math.round(x)), y: Math.max(0, Math.round(y)) }
}

function moveRect(rect, dx, dy, sw, sh) {
  var x = Math.min(Math.max(0, rect.x + dx), Math.max(0, sw - rect.w))
  var y = Math.min(Math.max(0, rect.y + dy), Math.max(0, sh - rect.h))
  return { x: x, y: y, w: rect.w, h: rect.h }
}

// Grid snapping applies to the offsets from the chosen corner, so a widget at
// x: 48 stays at 48 on a 24-grid and layouts never drift. size <= 0 = off.
function snapPlace(place, size) {
  var g = Number(size) || 0
  if (g <= 0) return place
  return { corner: place.corner, x: Math.max(0, Math.round(place.x / g) * g), y: Math.max(0, Math.round(place.y / g) * g) }
}

if (typeof module !== "undefined") module.exports = { rectFor, placeFor, moveRect, snapPlace }
