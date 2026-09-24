import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: pagination — horizontal group of page buttons.
RowLayout {
    required property var node
    readonly property var props: node ? node.properties : ({})

    spacing: Style.num(props, "gap", 2)

    Repeater {
        model: node ? node.children : []
        delegate: LuiNodeView {
            required property var modelData
            node: modelData }
    }
}
