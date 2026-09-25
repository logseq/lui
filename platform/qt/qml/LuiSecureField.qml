import QtQuick
import QtQuick.Controls
import "LuiStyle.js" as Style

// Wire kind: secure-field — password input.
TextField {
    id: field
    required property var node
    readonly property var props: node ? node.properties : ({})

    placeholderText: Style.str(props, "placeholder", "")
    echoMode: TextInput.Password
    enabled: props["enabled"] !== false
    color: Style.nodeColor(node, props["foreground"], palette.text)
    implicitWidth: 200
    Component.onCompleted: {
        if (props["autofocus"] === true) forceActiveFocus()
        sync()
    }

    property string wireText: Style.str(props, "text", "")
    property bool updating: false
    function sync() {
        if (text !== wireText) {
            updating = true
            text = wireText
            updating = false
        }
    }
    onWireTextChanged: sync()
    onTextChanged: if (!updating) node.textChanged(text)
    onAccepted: node.submit()

    implicitHeight: 34
    background.implicitHeight: 34
}
