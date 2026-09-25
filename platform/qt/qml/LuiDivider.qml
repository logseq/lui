import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: divider — hairline rule; orientation follows the parent
// container (horizontal in columns, vertical in rows).
Rectangle {
    required property var node
    readonly property var props: node ? node.properties : ({})

    readonly property bool horizontal:
        !node || !node.parent || String(node.parent.kind) !== "row"
    SystemPalette { id: divPal }
    implicitWidth: horizontal ? 40 : 1
    implicitHeight: horizontal ? 1 : 40
    Layout.fillWidth: horizontal
    Layout.fillHeight: !horizontal
    color: Style.nodeColor(node, props["foreground"], divPal.mid)
}
