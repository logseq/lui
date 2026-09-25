import QtQuick
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: breadcrumb — horizontal trail of button children with
// separators.
RowLayout {
    id: crumb
    required property var node
    readonly property var props: node ? node.properties : ({})

    SystemPalette { id: crumbPal }
    spacing: Style.num(props, "gap", 4)

    Repeater {
        model: crumb.node ? crumb.node.children : []
        delegate: RowLayout {
            required property int index
            required property var modelData
            spacing: crumb.spacing

            LuiNodeView { node: modelData }

            Text {
                visible: index < crumb.node.children.length - 1
                text: "/"
                color: crumbPal.mid
                font.pixelSize: 12
            }
        }
    }

    Item { Layout.fillWidth: true }
}
