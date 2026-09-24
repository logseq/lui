import QtQuick
import QtQuick.Controls
import "LuiStyle.js" as Style

// Wire kind: switch — platform switch control.
Switch {
    id: control
    required property var node
    readonly property var props: node ? node.properties : ({})

    text: Style.str(props, "text", "")
    checked: props["checked"] === true
    enabled: props["enabled"] !== false
    checkable: false // checked state is owned by the wire

    onClicked: node.toggle(!control.checked)
}
