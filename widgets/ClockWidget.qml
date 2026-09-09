import QtQuick
import qs.Commons

WidgetCard {
  id: root
  property string timeFormat: String(config.timeFormat || "HH:mm")
  property string dateFormat: String(config.dateFormat || "dddd d MMMM")
  property date now: new Date()

  Timer {
    interval: 1000; running: true; repeat: true; triggeredOnStart: true
    onTriggered: root.now = new Date()
  }

  Column {
    spacing: Math.round(Style.space(2) * root.scale_)
    WidgetText {
      outlineColor: root.outlineColor; halo: root.halo
      text: Qt.formatDateTime(root.now, root.timeFormat)
      color: root.textColor
      font.family: Style.font.resolvedFamily
      font.pixelSize: Math.round(Style.font.displayLarge * 2.4 * root.scale_)
      font.weight: Font.Light
      anchors.right: root.align === "right" ? parent.right : undefined
    }
    WidgetText {
      outlineColor: root.outlineColor; halo: root.halo
      text: Qt.formatDateTime(root.now, root.dateFormat)
      visible: root.dateFormat !== ""
      color: root.mutedColor
      font.family: Style.font.resolvedFamily
      font.pixelSize: Math.round(Style.font.heading * root.scale_)
      anchors.right: root.align === "right" ? parent.right : undefined
    }
  }
}
