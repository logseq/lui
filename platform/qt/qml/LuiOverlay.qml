import QtQuick

// Wire kind: overlay — children after the first float over the first child
// without affecting its layout. Each overlay child positions itself by its
// own `alignment` property, falling back to the overlay's (default center).
Item {
    id: overlay
    required property var node
    readonly property var props: node ? node.properties : ({})

    implicitWidth: rep.itemAt(0) ? rep.itemAt(0).implicitWidth : 0
    implicitHeight: rep.itemAt(0) ? rep.itemAt(0).implicitHeight : 0

    function alignmentOf(item) {
        var childProps = item && item.node ? item.node.properties : null
        return (childProps && childProps.alignment) || props.alignment ||
               "center"
    }

    function anchorOverlay(item) {
        switch (alignmentOf(item)) {
        case "top-leading":
            item.anchors.top = overlay.top
            item.anchors.left = overlay.left
            break
        case "top":
            item.anchors.top = overlay.top
            item.anchors.horizontalCenter = overlay.horizontalCenter
            break
        case "top-trailing":
            item.anchors.top = overlay.top
            item.anchors.right = overlay.right
            break
        case "leading":
            item.anchors.left = overlay.left
            item.anchors.verticalCenter = overlay.verticalCenter
            break
        case "trailing":
            item.anchors.right = overlay.right
            item.anchors.verticalCenter = overlay.verticalCenter
            break
        case "bottom-leading":
            item.anchors.bottom = overlay.bottom
            item.anchors.left = overlay.left
            break
        case "bottom":
            item.anchors.bottom = overlay.bottom
            item.anchors.horizontalCenter = overlay.horizontalCenter
            break
        case "bottom-trailing":
            item.anchors.bottom = overlay.bottom
            item.anchors.right = overlay.right
            break
        default:
            item.anchors.centerIn = overlay
        }
    }

    Repeater {
        id: rep
        model: overlay.node ? overlay.node.children : []
        delegate: LuiNodeView {
            required property var modelData
            required property int index
            node: modelData
        }
        onItemAdded: function(index, item) {
            if (index === 0) {
                item.anchors.fill = overlay
            } else {
                overlay.anchorOverlay(item)
            }
        }
    }
}
