import QtQuick
import qs.Commons
// The plugin's widget kit: WidgetCard (frame, colours, outline) and WidgetText.
// This relative path is the same on every `omarchy plugin add` install.
import "../../plugins/homelab.desktop-widgets/widgets"

// Drop-in widget "hello". `config` is injected with your type.json fields
// (defaults applied) plus the common keys. Use root.textColor / mutedColor /
// outlineColor / halo / scale_ so it follows the theme and the config.
WidgetCard {
  id: root
  readonly property string name: String(config.name || "world")
  readonly property bool shout: config.shout === true

  Column {
    spacing: Math.round(Style.space(2) * root.scale_)
    WidgetText {
      outlineColor: root.outlineColor; halo: root.halo
      text: root.shout ? ("HELLO, " + root.name.toUpperCase() + "!") : ("hello, " + root.name)
      color: root.textColor
      font.family: Style.font.resolvedFamily
      font.pixelSize: Math.round(Style.font.heading * root.scale_)
    }
    WidgetText {
      outlineColor: root.outlineColor; halo: root.halo
      text: "drop-in widget · edit ~/.config/omarchy/desktop-widgets.d/hello/"
      color: root.mutedColor
      font.family: Style.font.resolvedFamily
      font.pixelSize: Math.round(Style.font.caption * root.scale_)
    }
  }
}
