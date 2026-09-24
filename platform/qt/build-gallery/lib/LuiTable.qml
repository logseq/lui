import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: table — vertical stack of table-row children.
ColumnLayout {
    required property var node
    readonly property var props: node ? node.properties : ({})

    spacing: 0

    Repeater {
        model: node ? node.children : []
        delegate: LuiNodeView {
            required property var modelData
            node: modelData
            Layout.fillWidth: true
        }
    }
}
