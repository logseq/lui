import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: split — two panes divided by a draggable handle; the split
// fraction is owned by the wire ("value"), drags emit value-changed.
Item {
    id: split
    required property var node
    readonly property var props: node ? node.properties : ({})

    readonly property real fraction:
        Math.min(1, Math.max(0, Style.num(props, "value", 0.5)))
    readonly property real handleWidth: 8
    readonly property var first: node && node.children.length > 0
                                 ? node.children[0] : null
    readonly property var second: node && node.children.length > 1
                                  ? node.children[1] : null

    LuiNodeView {
        node: split.first
        x: 0
        y: 0
        width: Math.max(0, (split.width - split.handleWidth) * split.fraction)
        height: split.height
        clip: true
    }

    Rectangle {
        id: handle
        x: (split.width - split.handleWidth) * split.fraction
        width: split.handleWidth
        height: split.height
        color: handleMouse.containsMouse || handleMouse.pressed
               ? "#d4d4d8" : "transparent"

        Rectangle {
            anchors.centerIn: parent
            width: 1
            height: parent.height
            color: "#e4e4e7"
        }

        MouseArea {
            id: handleMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.SplitHCursor
            onPositionChanged: function(mouse) {
                if (!pressed || !split.node) return
                var gx = mapToItem(split, mouse.x, 0).x
                var f = gx / Math.max(1, split.width - handle.width)
                split.node.valueChanged(Math.min(1, Math.max(0, f)))
            }
        }
    }

    LuiNodeView {
        node: split.second
        x: handle.x + handle.width
        y: 0
        width: Math.max(0, split.width - x)
        height: split.height
        clip: true
    }
}
