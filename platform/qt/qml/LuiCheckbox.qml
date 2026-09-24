import QtQuick
import QtQuick.Controls
import "LuiStyle.js" as Style

// Wire kind: checkbox — checked flag toggled via toggle-changed.
CheckBox {
    id: checkbox
    required property var node
    readonly property var props: node ? node.properties : ({})

    text: Style.str(props, "text", "")
    checked: props["checked"] === true
    enabled: props["enabled"] !== false
    checkable: false // checked state is owned by the wire

    indicator: Rectangle {
        implicitWidth: 18
        implicitHeight: 18
        x: checkbox.leftPadding
        y: checkbox.topPadding + (checkbox.availableHeight - height) / 2
        radius: 4
        color: checkbox.checked ? "#007aff" : "transparent"
        border.color: checkbox.checked ? "#007aff" : "#a1a1aa"
        border.width: 1

        Image {
            anchors.centerIn: parent
            source: "icons/check.svg"
            width: 12
            height: 12
            visible: checkbox.checked
        }
    }

    contentItem: Text {
        text: checkbox.text
        color: checkbox.enabled ? "#18181b" : "#a1a1aa"
        font.pixelSize: 14
        verticalAlignment: Text.AlignVCenter
        leftPadding: checkbox.indicator.width + 8
    }

    onClicked: node.toggle(!checkbox.checked)
}
