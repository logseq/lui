import QtQuick
import "LuiStyle.js" as Style

// Wire kind: bottom-tab — one destination page inside bottom-tabs; its
// children stack to fill the body.
Item {
    required property var node
    readonly property var props: node ? node.properties : ({})

    Repeater {
        model: node ? node.children : []
        delegate: LuiNodeView {
            required property var modelData
            node: modelData
            anchors.fill: parent
        }
    }
}
