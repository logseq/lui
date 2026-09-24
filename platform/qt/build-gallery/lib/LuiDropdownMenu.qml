import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: dropdown-menu — overlay surface anchored to the preceding
// sibling (LuiStack hands it `anchorItem` through LuiNodeView).
Item {
    id: menu
    required property var node
    property Item anchorItem: null
    readonly property var props: node ? node.properties : ({})

    implicitWidth: popup.width
    implicitHeight: 0

    Popup {
        id: popup
        padding: 4
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onClosed: if (menu.node) menu.node.dismiss()

        x: {
            if (!menu.anchorItem) return 0
            var p = menu.anchorItem.mapToItem(menu, 0, 0)
            return p.x
        }
        y: {
            if (!menu.anchorItem) return 0
            var p = menu.anchorItem.mapToItem(menu, 0, menu.anchorItem.height + 4)
            return p.y
        }

        background: Rectangle {
            radius: 8
            color: "#ffffff"
            border.color: "#e4e4e7"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: Style.num(menu.props, "gap", 0)

            Repeater {
                model: menu.node ? menu.node.children : []
                delegate: LuiNodeView {
            required property var modelData
            node: modelData }
            }
        }
    }

    Component.onCompleted: popup.open()
}
