import QtQuick
import qs.Commons
import qs.Ui

// Bar icon that exists only while arrange mode is armed. Click disarms,
// right-click opens the editor. Optional: add with
// `omarchy plugin enable homelab.desktop-widgets right`.
BarWidget {
  id: root
  moduleName: "homelab.desktop-widgets"
  readonly property var svc: bar && bar.shell && typeof bar.shell.serviceFor === "function" ? bar.shell.serviceFor("homelab.desktop-widgets") : null
  readonly property bool armed: !!svc && svc.arranging === true
  visible: armed
  implicitWidth: armed ? icon.implicitWidth + Style.space(12) : 0
  implicitHeight: barSize
  Text { id: icon; anchors.centerIn: parent; text: "󰆾"; color: bar ? bar.urgent : Color.urgent; font.family: Style.font.family; font.pixelSize: Style.font.icon }
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(m) {
      if (m.button === Qt.RightButton) { if (bar && bar.shell && typeof bar.shell.toggle === "function") bar.shell.toggle("homelab.desktop-widgets", "{}") }
      else if (root.svc) root.svc.setArranging(false)
    }
  }
}
