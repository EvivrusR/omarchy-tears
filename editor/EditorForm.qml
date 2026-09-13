import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../widgets/EditorModel.js" as Model
import "../widgets/Pet.js" as Pet

// The form for one entry, generated from the registry: common fields, then
// a header with the type's display name, then the type's own fields.
Flickable {
  id: root
  property var entry: null
  property var registry: null
  property var looks: null
  property string publishedName: ""
  signal edited(string key, var value)
  contentHeight: column.implicitHeight
  contentWidth: width
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  // `showWhen: {key: value}` on a field hides it until every named key has that value.
  function shown(f) {
    if (!f.showWhen) return true
    for (var k in f.showWhen) if (String(Model.valueOf(entry, k, registry)) !== String(f.showWhen[k])) return false
    return true
  }
  readonly property var fields: entry && registry ? Model.fieldsFor(String(entry.type || ""), registry).filter(function(f) { return f.type !== "type" && shown(f) }) : []
  readonly property int firstTypeField: {
    var t = entry && registry && registry.types ? registry.types[entry.type] : null
    var own = t && t.fields ? t.fields.map(function(f) { return f.key }) : []
    for (var i = 0; i < fields.length; i++) if (own.indexOf(fields[i].key) !== -1) return i
    return fields.length
  }
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
        Text {
          visible: modelData.key === "name" && root.publishedName !== "" && root.publishedName !== Pet.petName(root.entry)
          Layout.fillWidth: true; Layout.leftMargin: Style.space(190) + Style.spacing.md
          wrapMode: Text.WordWrap; color: Color.urgent; font.family: Style.font.family; font.pixelSize: Style.font.caption
          text: "another pet is already '" + Pet.petName(root.entry) + "' — this one publishes as pets." + root.publishedName + " (give it a name to pick your own)"
        }
        Text {
          visible: modelData.key === "sheet" && root.entry && String(root.entry.type) === "pet"
          Layout.fillWidth: true; Layout.leftMargin: Style.space(190) + Style.spacing.md
          wrapMode: Text.WordWrap; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption
          text: {
            if (!root.looks) return "Looks: idle, running, waving, jumping, failed, waiting, review (contract; measured once the pet renders)"
            var have = root.looks.filter(function(l) { return l.present })
            return "Looks: " + have.map(function(l) { return l.name + " ×" + l.frames }).join(", ") + " (" + have.length + " of " + root.looks.length + ")"
          }
        }
      }
    }
    Item { height: Style.spacing.lg }
  }
}
