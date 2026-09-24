import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: stack — z-ordered overlapping children. Overlay kinds
// (dropdown-menu, tooltip) anchor to the preceding sibling.
Item {
    id: stack
    required property var node
    readonly property var props: node ? node.properties : ({})

    implicitWidth: childrenRect.width
    implicitHeight: childrenRect.height

    Repeater {
        id: rep
        model: stack.node ? stack.node.children : []
        delegate: LuiNodeView {
            required property var modelData
            node: modelData
            anchors.fill: parent
            visible: {
                var k = node ? node.kind : ""
                return k !== "dropdown-menu" && k !== "context-menu" &&
                       k !== "tooltip"
            }
        }
        onItemAdded: function(index, item) {
            item.overlayAnchor = index > 0 ? rep.itemAt(index - 1) : stack
        }
    }
}
