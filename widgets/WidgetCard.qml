import QtQuick
import qs.Commons

// Frame shared by every widget: optional themed backdrop, padding, scale.
// `config` is the raw JSON entry from desktop-widgets.json.
Item {
  id: card
  property var config: ({})
  default property alias content: inner.data

  readonly property real scale_: Math.max(0.25, Number(config.scale || 1))
  readonly property real backdrop: Math.max(0, Math.min(1, Number(config.backdrop || 0)))
  property int pad: Math.round(Style.space(12) * scale_)   // widgets may override (shape uses 0)
  readonly property string align: {
    var a = String(config.align || "auto")
    if (a === "left" || a === "right") return a
    return String(config.corner || "top-right").indexOf("right") !== -1 ? "right" : "left"
  }

  // Theme token (foreground|background|accent|muted|urgent) or any Qt colour
  // string such as "#1a1a1a". Falls back to the theme foreground / muted.
  function resolveColor(value, fallback) {
    var v = String(value || "").trim()
    if (!v) return fallback
    switch (v) {
      case "foreground": return Color.foreground
      case "background": return Color.background
      case "accent": return Color.accent
      case "muted": return Color.muted
      case "urgent": return Color.urgent
    }
    var c = Qt.color(v)
    return c.valid === false ? fallback : c
  }
  // Arrays that travel through the shell's model plumbing arrive as Qt lists,
  // which fail Array.isArray; normalise to a plain JS array (null if not a list).
  function listOf(v) {
    if (Array.isArray(v)) return v
    if (v && typeof v === "object" && typeof v.length === "number") { var a = []; for (var i = 0; i < v.length; i++) a.push(v[i]); return a }
    return null
  }
  readonly property color textColor: resolveColor(config.color, Color.foreground)
  readonly property color mutedColor: resolveColor(config.mutedColor, Color.muted)
  // Outline + halo behind all text. `"outline": ""` turns it off.
  readonly property color outlineColor: config.outline === undefined ? Qt.color("#000000") : resolveColor(config.outline, "transparent")
  readonly property real halo: config.halo === undefined ? 0.7 : Math.max(0, Math.min(1, Number(config.halo)))

  implicitWidth: inner.implicitWidth + 2 * pad
  implicitHeight: inner.implicitHeight + 2 * pad

  Rectangle {
    anchors.fill: parent
    visible: card.backdrop > 0
    radius: Style.cornerRadius
    color: Util.alpha(Color.popups.background, card.backdrop)
    border.width: card.backdrop > 0 ? Style.normalBorderWidth : 0
    border.color: Util.alpha(Color.popups.border, card.backdrop * 0.6)
  }

  Item {
    id: inner
    x: card.pad
    y: card.pad
    implicitWidth: childrenRect.width
    implicitHeight: childrenRect.height
  }
}
