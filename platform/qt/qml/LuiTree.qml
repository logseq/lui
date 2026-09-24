import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: tree — vertical stack of tree-item (list-item role) rows or a
// virtual-list child.
ColumnLayout {
    required property var node
    readonly property var props: node ? node.properties : ({})

    spacing: Style.num(props, "gap", 0)

    Repeater {
        model: node ? node.children : []
        delegate: LuiNodeView {
            required property var modelData
            node: modelData
            Layout.fillWidth: true
        }
    }
}
