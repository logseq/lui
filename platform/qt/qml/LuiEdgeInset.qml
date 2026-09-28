import QtQuick

// Wire kind: edge-inset — children after the first are pinned to `edge`
// while the first child fills the view beneath them. `visible` hides the
// pinned region in place; `gap` insets it from the pinned edge.
Item {
    id: edgeInset
    required property var node
    readonly property var props: node ? node.properties : ({})

    readonly property string edge: props.edge || "top"
    readonly property bool pinnedVisible: props.visible !== false
    readonly property bool sideEdge: edge === "leading" || edge === "trailing"
    readonly property real gap: props.gap || 0
    readonly property var pinnedChildren: node ? node.children.slice(1) : []

    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

    LuiNodeView {
        id: content
        anchors.fill: parent
        node: edgeInset.node && edgeInset.node.children.length > 0
              ? edgeInset.node.children[0] : null
    }

    // Pinned children group into one region so they stack across the edge
    // instead of overlapping (column under top/bottom, row along the sides,
    // matching the Apple backend).
    Item {
        id: pinnedRegion
        visible: edgeInset.pinnedVisible
        implicitWidth: pinnedFlow.implicitWidth
        implicitHeight: pinnedFlow.implicitHeight

        // Bound (not imperative) anchors so an `edge` change re-anchors;
        // `undefined` clears the anchor.
        anchors.top: edgeInset.edge === "top" || edgeInset.sideEdge
                     ? parent.top : undefined
        anchors.bottom: edgeInset.edge === "bottom" || edgeInset.sideEdge
                        ? parent.bottom : undefined
        anchors.left: !edgeInset.sideEdge || edgeInset.edge === "leading"
                      ? parent.left : undefined
        anchors.right: !edgeInset.sideEdge || edgeInset.edge === "trailing"
                       ? parent.right : undefined
        anchors.topMargin: edgeInset.edge === "top" ? edgeInset.gap : 0
        anchors.bottomMargin: edgeInset.edge === "bottom" ? edgeInset.gap : 0
        anchors.leftMargin: edgeInset.edge === "leading" ? edgeInset.gap : 0
        anchors.rightMargin: edgeInset.edge === "trailing" ? edgeInset.gap : 0

        Grid {
            id: pinnedFlow
            flow: edgeInset.sideEdge ? Grid.LeftToRight : Grid.TopToBottom
            columns: edgeInset.sideEdge ? edgeInset.pinnedChildren.length : 1
            Repeater {
                model: edgeInset.pinnedChildren
                delegate: LuiNodeView {
                    required property var modelData
                    node: modelData
                }
            }
        }
    }
}
