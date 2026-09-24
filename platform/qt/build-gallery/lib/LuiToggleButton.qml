import QtQuick
import QtQuick.Controls
import "LuiStyle.js" as Style

// Wire kind: toggle-button — pressable selected/unselected button.
Button {
    id: button
    required property var node
    readonly property var props: node ? node.properties : ({})

    text: Style.str(props, "text", "")
    enabled: props["enabled"] !== false
    checkable: false // state comes from the wire, not the control
    readonly property bool selected: props["selected"] === true

    icon.source: Style.iconSource(Style.str(props, "icon", ""))
    icon.width: 14
    icon.height: 14

    padding: Style.controlPadding(Style.str(props, "size", "default"))

    background: Rectangle {
        implicitWidth: 80
        implicitHeight: 32
        radius: 6
        color: !button.enabled ? "#e4e4e7"
               : button.selected ? (button.down ? "#0060c9" : "#007aff")
               : button.down ? "#f4f4f5" : "transparent"
        border.color: button.selected ? "transparent" : "#d4d4d8"
        border.width: button.selected ? 0 : 1
    }

    palette.buttonText: !button.enabled ? "#a1a1aa"
                        : button.selected ? "#ffffff" : "#18181b"

    onClicked: node.toggle(!selected)
    onPressAndHold: if (props["long-press-enabled"] === true) node.longPress()
}
