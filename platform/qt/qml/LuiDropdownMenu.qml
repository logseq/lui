import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: dropdown-menu — overlay surface anchored to the preceding
// sibling (LuiStack hands it `anchorItem` through LuiNodeView). With no
// anchor it renders its items inline instead of opening a Popup that
// would hover over unrelated content.
Item {
    id: menu
    required property var node
    property Item anchorItem: null
    readonly property var props: node ? node.properties : ({})

    implicitWidth: menu.anchorItem ? popup.width : inlineCol.implicitWidth
    implicitHeight: menu.anchorItem ? 0 : inlineCol.implicitHeight

    ColumnLayout {
        id: inlineCol
        visible: !menu.anchorItem
        spacing: Style.num(menu.props, "gap", 0)

        Repeater {
            model: menu.node ? menu.node.children : []
            delegate: LuiNodeView {
            required property var modelData
            node: modelData }
        }
    }

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

    Component.onCompleted: if (menu.anchorItem) popup.open()
    onAnchorItemChanged: if (menu.anchorItem && !popup.opened) popup.open()
}
