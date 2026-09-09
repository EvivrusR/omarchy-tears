// Placement maths for arrange mode. Screen-space logical pixels; corners as
// in the registry. Shared by the overlay (QML) and node tests.
function rectFor(corner, x, y, w, h, sw, sh) {
  var right = String(corner).indexOf("right") !== -1
  var bottom = String(corner).indexOf("bottom") === 0
  return { x: right ? sw - x - w : x, y: bottom ? sh - y - h : y, w: w, h: h }
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

if (typeof module !== "undefined") module.exports = { rectFor, placeFor, moveRect }
