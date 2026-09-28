import QtQuick
import QtQuick.Layouts

// Wire kind: file-picker — non-visual element; the Qt backend does not
// present a native file dialog. Children (if any) render inline.
Item {
    id: picker
    required property var node
    readonly property var props: node ? node.properties : ({})

    implicitWidth: col.implicitWidth
    implicitHeight: col.implicitHeight

    ColumnLayout {
        id: col
        spacing: 0
        Repeater {
            model: picker.node ? picker.node.children : []
            delegate: LuiNodeView {
                required property var modelData
                node: modelData
            }
        }
    }
}
