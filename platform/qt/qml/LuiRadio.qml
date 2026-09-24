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


    onClicked: node.change()
}
