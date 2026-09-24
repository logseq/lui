import QtQuick
import QtQml
import "LuiStyle.js" as Style

// Wire kind: tooltip — overlay surface anchored to the preceding sibling.
Item {
    id: tip
    required property var node
    property Item anchorItem: null
    readonly property var props: node ? node.properties : ({})

    implicitWidth: 0
    implicitHeight: 0

    SystemPalette { id: tipPal }

    Rectangle {
        x: {
            if (!tip.anchorItem) return 0
            return tip.anchorItem.mapToItem(tip, 0, 0).x
        }
        y: {
            if (!tip.anchorItem) return 0
            return tip.anchorItem.mapToItem(tip, 0, tip.anchorItem.height + 6).y
        }
        implicitWidth: label.implicitWidth + 16
        implicitHeight: label.implicitHeight + 10
        radius: 6
        color: tipPal.toolTipBase

        Text {
            id: label
            anchors.centerIn: parent
            text: Style.str(tip.props, "text", "")
            color: tipPal.toolTipText
            font.pixelSize: 12
        }
    }
}
