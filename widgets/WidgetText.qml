import QtQuick
import QtQuick.Effects

// Text with an optional crisp outline plus a soft dark halo, so widgets stay
// readable on any wallpaper. `outlineColor` with alpha 0 disables both.
// The halo is drawn once for the whole card by WidgetCard (one offscreen layer
// per widget, not one per line of text); `ownHalo: true` draws it here instead,
// for text in a card that turned the shared halo off.
Text {
  id: t
  property color outlineColor: "transparent"
  property real halo: 0
  property bool ownHalo: false

  // A 1px outline swallows small glyphs; below this size the halo does the work.
  property int outlineMinPx: 15
  style: outlineColor.a > 0 && font.pixelSize >= outlineMinPx ? Text.Outline : Text.Normal
  styleColor: outlineColor
  renderType: Text.QtRendering

  layer.enabled: ownHalo && outlineColor.a > 0 && halo > 0
  layer.effect: MultiEffect {
    shadowEnabled: true
    shadowColor: t.outlineColor
    shadowOpacity: t.halo
    shadowBlur: font.pixelSize >= outlineMinPx ? 0.6 : 0.45
    shadowScale: 1.04
    shadowHorizontalOffset: 0
    shadowVerticalOffset: 0
    autoPaddingEnabled: true
  }
}
