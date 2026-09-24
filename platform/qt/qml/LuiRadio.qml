import QtQuick
import QtQuick.Controls
import "LuiStyle.js" as Style

// Wire kind: radio — one option inside a radio-group; selection goes
// through the change event.
RadioButton {
    id: radio
    required property var node
    readonly property var props: node ? node.properties : ({})

    text: Style.str(props, "text", "")
    checked: props["checked"] === true
    enabled: props["enabled"] !== false
    checkable: false // checked state is owned by the wire

    indicator: Rectangle {
        implicitWidth: 18
        implicitHeight: 18
        x: radio.leftPadding
        y: radio.topPadding + (radio.availableHeight - height) / 2
        radius: 9
        color: "transparent"
        border.color: radio.checked ? "#007aff" : "#a1a1aa"
        border.width: 1

        Rectangle {
            anchors.centerIn: parent
            width: 10
            height: 10
            radius: 5
            color: "#007aff"
            visible: radio.checked
        }
    }

    contentItem: Text {
        text: radio.text
        color: radio.enabled ? "#18181b" : "#a1a1aa"
        font.pixelSize: 14
        verticalAlignment: Text.AlignVCenter
        leftPadding: radio.indicator.width + 8
    }

    onClicked: node.change()
}
