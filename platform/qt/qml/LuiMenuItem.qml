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
            color: !item.enabled ? item.palette.placeholderText
                   : (item.hovered || item.down) ? item.palette.highlightedText
                   : item.destructive ? "#dc2626" : item.palette.text
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
            color: item.palette.mid
        }
    }


    background: Rectangle {
        color: item.down || item.hovered ? item.palette.highlight : "transparent"
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
