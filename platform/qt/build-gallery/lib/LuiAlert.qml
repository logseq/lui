import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: alert — status callout tinted by variant
// (default/primary/secondary/outline/ghost/destructive).
Rectangle {
    id: alert
    required property var node
    readonly property var props: node ? node.properties : ({})

    function variantColors() {
        switch (Style.str(props, "variant", "default")) {
        case "primary": return ["#e8f2ff", "#007aff", "#0f4a8a"]
        case "secondary": return ["#f4f4f5", "#e4e4e7", "#18181b"]
        case "outline": return ["transparent", "#e4e4e7", "#18181b"]
        case "ghost": return ["transparent", "transparent", "#18181b"]
        case "destructive": return ["#fee2e2", "#ef4444", "#991b1b"]
        default: return ["#f4f4f5", "#e4e4e7", "#18181b"]
        }
    }

    readonly property var _colors: variantColors()
    color: _colors[0]
    border.color: Style.color(props["border-color"], _colors[1])
    border.width: Style.num(props, "border-width", 1)
    radius: Style.num(props, "corner-radius", 8)

    implicitWidth: col.implicitWidth + 2 * pad
    implicitHeight: col.implicitHeight + 2 * pad
    property real pad: 12

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: alert.pad
        spacing: Style.num(props, "gap", 6)

        Text {
            visible: Style.str(alert.props, "text", "") !== ""
            text: Style.str(alert.props, "text", "")
            color: Style.color(alert.props["foreground"], alert._colors[2])
            font.pixelSize: 14
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Repeater {
            model: alert.node ? alert.node.children : []
            delegate: LuiNodeView {
            required property var modelData
                node: modelData
                Layout.fillWidth: true
            }
        }
    }
}
