import QtQuick
import QtQuick.Controls
import "LuiStyle.js" as Style

// Wire kind: select — picker trigger; pressing emits press so the runtime
// can attach a dropdown-menu child.
Button {
    id: select
    required property var node
    readonly property var props: node ? node.properties : ({})

    enabled: props["enabled"] !== false
    implicitWidth: Math.max(160, contentItem.implicitWidth + 30)
    implicitHeight: 34

    contentItem: Row {
        spacing: 6
        leftPadding: 10
        Text {
            text: Style.str(select.props, "text", "") !== ""
                  ? Style.str(select.props, "text", "")
                  : Style.str(select.props, "placeholder", "")
            color: Style.str(select.props, "text", "") !== ""
                   ? Style.color(select.props["foreground"], "#18181b")
                   : "#a1a1aa"
            font.pixelSize: 14
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            width: parent.width - 20
        }
    }

    indicator: Text {
        text: "▾"
        color: "#71717a"
        anchors {
            right: parent.right
            rightMargin: 8
            verticalCenter: parent.verticalCenter
        }
    }

    background: Rectangle {
        radius: 6
        color: select.enabled ? "#ffffff" : "#f4f4f5"
        border.color: select.down ? "#007aff" : "#d4d4d8"
        border.width: 1
    }

    onClicked: node.press()
}
