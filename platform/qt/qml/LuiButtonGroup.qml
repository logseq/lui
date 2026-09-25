import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: button-group — horizontal group of button children.
RowLayout {
    required property var node
    readonly property var props: node ? node.properties : ({})

    spacing: Style.num(props, "gap", 4)

    Repeater {
        model: node ? node.children : []
        delegate: LuiNodeView {
            required property var modelData
            node: modelData }
    }

    Item { Layout.fillWidth: true }
}
