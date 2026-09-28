import QtQuick

// Wire kind: edge-inset — children after the first are pinned to `edge`
// while the first child fills the view beneath them. `visible` hides the
// pinned children in place; `gap` is the spacing between content and the
// pinned children (here: pinned children simply overlay at the edge).
Item {
    id: edgeInset
    required property var node
    readonly property var props: node ? node.properties : ({})

    readonly property string edge: props.edge || "top"
    readonly property bool pinnedVisible: props.visible !== false
    readonly property bool sideEdge: edge === "leading" || edge === "trailing"

    implicitWidth: rep.itemAt(0) ? rep.itemAt(0).implicitWidth : 0
    implicitHeight: rep.itemAt(0) ? rep.itemAt(0).implicitHeight : 0

    Repeater {
        id: rep
        model: edgeInset.node ? edgeInset.node.children : []
        delegate: LuiNodeView {
            required property var modelData
            required property int index
            node: modelData
            visible: index === 0 || edgeInset.pinnedVisible
        }
        onItemAdded: function(index, item) {
            if (index === 0) {
                item.anchors.fill = edgeInset
                return
            }
            switch (edgeInset.edge) {
            case "bottom":
                item.anchors.bottom = edgeInset.bottom
                item.anchors.left = edgeInset.left
                item.anchors.right = edgeInset.right
                break
            case "leading":
                item.anchors.left = edgeInset.left
                item.anchors.top = edgeInset.top
                item.anchors.bottom = edgeInset.bottom
                break
            case "trailing":
                item.anchors.right = edgeInset.right
                item.anchors.top = edgeInset.top
                item.anchors.bottom = edgeInset.bottom
                break
            default:
                item.anchors.top = edgeInset.top
                item.anchors.left = edgeInset.left
                item.anchors.right = edgeInset.right
            }
        }
    }
}
