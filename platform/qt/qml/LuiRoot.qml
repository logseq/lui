import QtQuick

// Wire kind: root. Owns exactly one child and stretches it.
Item {
    required property var node

    implicitWidth: childView.implicitWidth
    implicitHeight: childView.implicitHeight

    LuiNodeView {
        id: childView
        anchors.fill: parent
        node: node && node.children.length > 0 ? node.children[0] : null
    }
}
