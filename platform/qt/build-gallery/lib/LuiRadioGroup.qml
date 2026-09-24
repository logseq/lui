import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: radio-group — vertical stack of radio children.
ColumnLayout {
    required property var node
    readonly property var props: node ? node.properties : ({})

    spacing: Style.num(props, "gap", 8)

    Repeater {
        model: node ? node.children : []
        delegate: LuiNodeView {
            required property var modelData
            node: modelData }
    }
}
