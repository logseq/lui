import QtQuick
import QtQuick.Controls
import "LuiStyle.js" as Style

// Wire kind: list — vertical list of children (non-virtualized).
ListView {
    id: list
    required property var node
    readonly property var props: node ? node.properties : ({})

    model: node ? node.children : []
    spacing: Style.num(props, "gap", 0)
    clip: true
    implicitWidth: 200
    implicitHeight: 120
    interactive: contentHeight > height

    delegate: LuiNodeView {
        required property var modelData
        node: modelData
        width: list.width
    }
}
