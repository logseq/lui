import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: alert — status callout tinted by variant
// (default/primary/secondary/outline/ghost/destructive).
Frame {
    id: alert
    required property var node
    readonly property var props: node ? node.properties : ({})

    padding: 12

    contentItem: ColumnLayout {
        id: col
        spacing: Style.num(props, "gap", 6)

        Text {
            visible: Style.str(alert.props, "text", "") !== ""
            text: Style.str(alert.props, "text", "")
            color: Style.color(alert.props["foreground"], alert.palette.text)
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
