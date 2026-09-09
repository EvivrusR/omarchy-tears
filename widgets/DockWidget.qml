import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons

// A row of app icons that launch on click. The service gives this widget an
// input region (registry `input: true`); it launches the way Omarchy's own
// menu does, through gtk-launch under uwsm-app. Icons are tinted in the
// widget's text colour by default so any icon set matches the theme.
WidgetCard {
  id: root
  readonly property var apps: listOf(config.apps) || []
  readonly property int iconSize: Math.round(Number(config.iconSize || 32) * scale_)
  readonly property int gap: Math.round(Number(config.spacing !== undefined ? config.spacing : 8) * scale_)
  readonly property bool labels: config.labels === true
  readonly property bool themed: String(config.iconStyle || "themed") !== "original"
  readonly property real hoverScale: Math.max(1, Math.min(2, Number(config.hoverScale || 1.2)))
  pad: Math.round(Style.space(8) * scale_)
  // Room for the hover tooltip above the card, inside our own window.
  topInset: labels ? 0 : Math.round((Style.font.caption + Style.space(14)) * scale_)

  function entryFor(id) { return DesktopEntries.byId(String(id)) || DesktopEntries.heuristicLookup(String(id)) }
  function iconFor(entry) {
    var icon = entry ? String(entry.icon || "") : ""
    if (icon.charAt(0) === "/") return "file://" + icon
    var p = icon ? Quickshell.iconPath(icon, true) : ""
    return p && p.length ? p : Quickshell.iconPath("application-x-executable", true)
  }
  function launch(id) { Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", String(id) + ".desktop"]) }

  Row {
    spacing: root.gap
    WidgetText {
      visible: root.apps.length === 0
      outlineColor: root.outlineColor; halo: root.halo
      text: "dock: no apps — `desktop-widgets apps` lists ids"; color: root.mutedColor
      font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.caption * root.scale_)
    }
    Repeater {
      model: root.apps
      Column {
        id: cell
        required property var modelData
        readonly property string appId: String(modelData)
        // Re-evaluates once the desktop entries have loaded (they may lag the widget).
        readonly property var entry: { DesktopEntries.applications.values; return root.entryFor(appId) }
        readonly property string appName: entry ? String(entry.name) : appId
        spacing: Math.round(Style.space(3) * root.scale_)
        Item {
          width: root.iconSize; height: root.iconSize
          Image {
            id: img
            anchors.centerIn: parent
            width: root.iconSize; height: root.iconSize
            source: root.iconFor(cell.entry)
            sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
            smooth: true; mipmap: true
            visible: !root.themed
            scale: mouse.containsMouse ? root.hoverScale : 1
            opacity: mouse.pressed ? 0.6 : 1
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
          }
          // Themed: the icon's luminance, recoloured in the text colour (like a glyph).
          MultiEffect {
            visible: root.themed
            anchors.fill: img
            source: img
            colorization: 1.0
            colorizationColor: root.textColor
            scale: img.scale; opacity: img.opacity
          }
          MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.launch(cell.appId)
          }
        }
        WidgetText {
          visible: root.labels
          anchors.horizontalCenter: parent.horizontalCenter
          outlineColor: root.outlineColor; halo: root.halo
          text: cell.appName; color: root.mutedColor
          font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.caption * root.scale_)
          width: Math.min(implicitWidth, root.iconSize * 2); elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
        }
        // Tooltip lives in the card's top inset so it is never clipped by the window.
        Rectangle {
          visible: mouse.containsMouse && !root.labels
          parent: root
          x: Math.max(0, Math.min(root.width - width, cell.mapToItem(root, 0, 0).x + root.iconSize / 2 - width / 2))
          y: Math.max(0, root.topInset - height - Math.round(Style.space(4) * root.scale_))
          width: tip.implicitWidth + Style.space(12); height: tip.implicitHeight + Style.space(6)
          radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : 0
          color: Util.alpha(Color.popups.background, 0.92); border.width: 1; border.color: Color.popups.border
          Text { id: tip; anchors.centerIn: parent; text: cell.appName; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.caption }
        }
      }
    }
  }
}
