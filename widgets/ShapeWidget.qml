import QtQuick
import QtQuick.Effects
import qs.Commons

// Pure form: a translucent rect / pill / circle / line with no text, meant to
// sit behind other widgets (give it a lower `z`). Never takes input.
WidgetCard {
  id: root
  pad: 0
  readonly property string kind: String(config.kind || "rect")
  readonly property int w: Math.max(1, Math.round(Number(config.width || 320) * scale_))
  readonly property int h: kind === "circle" ? w : Math.max(1, Math.round(Number(config.height || 200) * scale_))
  readonly property real fillAlpha: config.alpha === undefined ? 0.4 : Math.max(0, Math.min(1, Number(config.alpha)))
  readonly property real borderAlpha: config.borderAlpha === undefined ? 1 : Math.max(0, Math.min(1, Number(config.borderAlpha)))
  readonly property int borderWidth: Math.max(0, Math.round(Number(config.borderWidth || 0) * scale_))
  readonly property real shadow: Math.max(0, Math.min(1, Number(config.shadow || 0)))

  Item {
    // The shadow needs room outside the shape, so the card is padded by it and
    // the shape drawn inset; layer padding is disabled to keep the size exact.
    readonly property int margin: root.shadow > 0 ? Math.round(24 * root.scale_) : 0
    implicitWidth: root.w + 2 * margin
    implicitHeight: root.h + 2 * margin

    Rectangle {
      id: shape
      x: parent.margin; y: parent.margin
      width: root.w; height: root.h
      radius: root.kind === "pill" ? height / 2 : root.kind === "circle" ? width / 2
            : Math.round(Number(root.config.radius === undefined ? 12 : root.config.radius) * root.scale_)
      color: Util.alpha(root.resolveColor(root.config.fill || "background", Color.background), root.fillAlpha)
      border.width: root.borderWidth
      border.color: root.borderWidth > 0 ? Util.alpha(root.resolveColor(root.config.border || "accent", Color.accent), root.borderAlpha) : "transparent"
      antialiasing: true

      layer.enabled: root.shadow > 0
      layer.samples: 4
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: "#000000"
        shadowOpacity: root.shadow
        shadowBlur: 1.0
        shadowScale: 1.0
        shadowHorizontalOffset: 0
        shadowVerticalOffset: Math.round(4 * root.scale_)
        autoPaddingEnabled: true
      }
    }
  }
}
