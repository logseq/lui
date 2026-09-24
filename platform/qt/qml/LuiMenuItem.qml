import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: menu-item — row inside a dropdown/context menu; a dropdown-menu
// child becomes a cascading submenu.
ItemDelegate {
    id: item
    required property var node
    readonly property var props: node ? node.properties : ({})

    enabled: props["enabled"] !== false
    padding: 8
    implicitHeight: 32
    implicitWidth: Math.max(160, contentItem.implicitWidth + 32)
    readonly property var submenu: {
        var kids = node ? node.children : []
        for (var i = 0; i < kids.length; ++i)
            if (kids[i] && kids[i].kind === "dropdown-menu") return kids[i]
        return null
    }
    readonly property bool destructive:
        Style.str(props, "variant", "") === "destructive"
    readonly property bool selected: props["selected"] === true

    contentItem: RowLayout {
        spacing: 8
        Image {
            visible: Style.str(item.props, "icon", "") !== ""
            source: Style.iconSource(Style.str(item.props, "icon", ""))
            Layout.preferredWidth: 16
            Layout.preferredHeight: 16
            fillMode: Image.PreserveAspectFit
        }
        Text {
            text: Style.str(item.props, "text", "")
            color: !item.enabled ? "#a1a1aa"
                   : item.destructive ? "#dc2626" : "#18181b"
            font.pixelSize: 13
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
        Image {
            visible: item.selected
            source: "icons/check.svg"
            Layout.preferredWidth: 14
            Layout.preferredHeight: 14
        }
        Text {
            visible: item.submenu !== null
            text: "▸"
            color: "#71717a"
        }
    }

    background: Rectangle {
        color: item.down || item.hovered ? "#f4f4f5" : "transparent"
        radius: 4
    }

    onClicked: {
        if (item.submenu !== null) {
            subPopup.open()
        } else {
            item.node.press()
        }
    }

    Popup {
        id: subPopup
        x: parent.width - 4
        y: -4
        padding: 4
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            radius: 8
            color: "#ffffff"
            border.color: "#e4e4e7"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 0
            Repeater {
                model: item.submenu ? item.submenu.children : []
                delegate: LuiNodeView {
            required property var modelData
            node: modelData }
            }
        }
    }
}
