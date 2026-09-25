import QtQuick
import "LuiStyle.js" as Style

// Wire kind: bottom-tab — one destination page inside bottom-tabs; its
// children stack to fill the body.
Item {
    required property var node
    readonly property var props: node ? node.properties : ({})

    implicitWidth: {
        var w = 0
        for (var i = 0; i < children.length; ++i)
            if (children[i].implicitWidth > w) w = children[i].implicitWidth
        return w
    }
    implicitHeight: {
        var h = 0
        for (var i = 0; i < children.length; ++i)
            if (children[i].implicitHeight > h) h = children[i].implicitHeight
        return h
    }

    Repeater {
        model: node ? node.children : []
        delegate: LuiNodeView {
            required property var modelData
            node: modelData
            anchors.fill: parent
        }
    }
}
