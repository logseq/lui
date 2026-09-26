// split-view: root of a tabbed split surface. Renders its single child and
// carries the shared visual settings (divider thickness, animation) which
// descendants read through their node.parent chain.
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property var node

    property bool fillsLayout: true

    readonly property real dividerThickness:
        Math.max(1, Number(node.prop("divider-thickness", 9)))
    readonly property bool animationEnabled:
        node.prop("animation", true) === true

    implicitWidth: childLoader.implicitWidth
    implicitHeight: childLoader.implicitHeight

    LuiNodeView {
        id: childLoader
        anchors.fill: parent
        node: root.node && root.node.children.length > 0
              ? root.node.children[0] : null
    }
}
