import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: list-item — pressable row with optional icon/text/subtitle.
ItemDelegate {
    id: item
    required property var node
    readonly property var props: node ? node.properties : ({})

    enabled: props["enabled"] !== false
    padding: 8
    implicitHeight: Math.max(40, contentItem.implicitHeight + 16)

    contentItem: RowLayout {
        spacing: 10
        Image {
            visible: Style.str(item.props, "icon", "") !== ""
            source: Style.iconSource(Style.str(item.props, "icon", ""))
            Layout.preferredWidth: 18
            Layout.preferredHeight: 18
            fillMode: Image.PreserveAspectFit
        }
        ColumnLayout {
            spacing: 1
            Layout.fillWidth: true
            Text {
                text: Style.str(item.props, "text", "")
                color: item.enabled ? "#18181b" : "#a1a1aa"
                font.pixelSize: 14
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Text {
                visible: Style.str(item.props, "subtitle", "") !== ""
                text: Style.str(item.props, "subtitle", "")
                color: "#71717a"
                font.pixelSize: 12
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }
    }

    background: Rectangle {
        color: item.down ? "#e4e4e7" : item.hovered ? "#f4f4f5" : "transparent"
        radius: 6
    }

    onClicked: {
        // treeitem rows select/expand via the change cascade, not press.
        if (props["role"] === "treeitem") node.change()
        else node.press()
    }
    onPressAndHold: if (props["long-press-enabled"] === true) node.longPress()
    onDoubleClicked: if (props["double-press-enabled"] === true) node.doublePress()
}
