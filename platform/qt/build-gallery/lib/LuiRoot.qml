import QtQuick

// Wire kind: root. Owns exactly one child and stretches it.
Item {
    id: root
    required property var node

    implicitWidth: childView.implicitWidth
    implicitHeight: childView.implicitHeight

    LuiNodeView {
        id: childView
        anchors.fill: parent
        node: root.node && root.node.children.length > 0
              ? root.node.children[0] : null
    }
}
