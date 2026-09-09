import QtQuick
import Quickshell
import qs.Commons

// A row of app icons that launch on click. The service gives this widget an
// input region (registry `input: true`); it launches the way Omarchy's own
// menu does, through gtk-launch under uwsm-app.
WidgetCard {
  id: root
  readonly property var apps: listOf(config.apps) || []
  readonly property int iconSize: Math.round(Number(config.iconSize || 40) * scale_)
  readonly property int gap: Math.round(Number(config.spacing !== undefined ? config.spacing : 10) * scale_)
  readonly property bool labels: config.labels === true
  readonly property real hoverScale: Math.max(1, Math.min(2, Number(config.hoverScale || 1.2)))

  function entryFor(id) { return DesktopEntries.byId(String(id)) || DesktopEntries.heuristicLookup(String(id)) }
  function iconFor(entry, id) {
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
        readonly property var entry: root.entryFor(appId)
        spacing: Math.round(Style.space(3) * root.scale_)
        Item {
          width: root.iconSize; height: root.iconSize
          Image {
            id: img
            anchors.centerIn: parent
            width: root.iconSize; height: root.iconSize
            source: root.iconFor(cell.entry, cell.appId)
            sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
            smooth: true; mipmap: true
            scale: mouse.containsMouse ? root.hoverScale : 1
            opacity: mouse.pressed ? 0.6 : 1
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
          }
          MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.launch(cell.appId)
          }
          Rectangle {
            visible: mouse.containsMouse && !root.labels
            anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.top; anchors.bottomMargin: Math.round(Style.space(6) * root.scale_)
            width: tip.implicitWidth + Style.space(10); height: tip.implicitHeight + Style.space(4)
            radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : 0
            color: Util.alpha(Color.popups.background, 0.9); border.width: 1; border.color: Color.popups.border
            Text { id: tip; anchors.centerIn: parent; text: cell.entry ? cell.entry.name : cell.appId; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          }
        }
        WidgetText {
          visible: root.labels
          anchors.horizontalCenter: parent.horizontalCenter
          outlineColor: root.outlineColor; halo: root.halo
          text: cell.entry ? cell.entry.name : cell.appId; color: root.mutedColor
          font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.caption * root.scale_)
          width: Math.min(implicitWidth, root.iconSize * 2); elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }
}
