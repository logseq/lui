import QtQuick
import QtQuick.Controls
import "LuiStyle.js" as Style

// Wire kind: input — compact single-line input (grouped style).
TextField {
    id: field
    required property var node
    readonly property var props: node ? node.properties : ({})

    placeholderText: Style.str(props, "placeholder", "")
    enabled: props["enabled"] !== false
    color: Style.color(props["foreground"], palette.text)
    implicitWidth: 180
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

    implicitHeight: 30
    background.implicitHeight: 30
}
