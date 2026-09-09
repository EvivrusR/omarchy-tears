import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../widgets/EditorModel.js" as Model

// The form for one entry, generated from the registry: common fields, then
// a header with the type's display name, then the type's own fields.
Flickable {
  id: root
  property var entry: null
  property var registry: null
  signal edited(string key, var value)
  contentHeight: column.implicitHeight
  contentWidth: width
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  readonly property var fields: entry && registry ? Model.fieldsFor(String(entry.type || ""), registry).filter(function(f) { return f.type !== "type" }) : []
  readonly property int firstTypeField: registry && registry.common ? registry.common.length - 1 : 0
  readonly property string typeName: entry && registry && registry.types && registry.types[entry.type] ? (registry.types[entry.type].displayName || entry.type) : String(entry ? entry.type : "")

  ColumnLayout {
    id: column
    width: root.width
    spacing: Style.spacing.md
    Text { visible: !root.entry; text: "Select a widget on the left, or add one."; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.body }
    Text { visible: !!root.entry && root.fields.length === 0; text: "Unknown type '" + (root.entry ? root.entry.type : "") + "' — fix it in the file."; color: Color.urgent; font.family: Style.font.family; font.pixelSize: Style.font.body }
    Repeater {
      model: root.fields
      delegate: ColumnLayout {
        required property var modelData
        required property int index
        Layout.fillWidth: true
        spacing: Style.spacing.md
        PanelSectionHeader { visible: index === root.firstTypeField; text: root.typeName.toUpperCase(); Layout.topMargin: Style.spacing.md }
        FieldControl {
          Layout.fillWidth: true
          field: modelData
          value: Model.valueOf(root.entry, modelData.key, root.registry)
          onEdited: function(key, value) { root.edited(key, value) }
        }
      }
    }
    Item { height: Style.spacing.lg }
  }
}
