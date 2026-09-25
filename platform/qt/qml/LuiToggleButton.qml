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

    highlighted: button.selected
    flat: Style.str(props, "variant", "default") === "ghost"
    implicitHeight: 32
    background.implicitWidth: 80
    background.implicitHeight: 32

    onClicked: node.toggle(!selected)
    onPressAndHold: if (props["long-press-enabled"] === true) node.longPress()
}
