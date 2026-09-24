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
    color: Style.color(props["foreground"], "#18181b")
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

    background: Rectangle {
        implicitWidth: 180
        implicitHeight: 30
        radius: 5
        color: field.enabled ? "#ffffff" : "#f4f4f5"
        border.color: field.activeFocus ? "#007aff" : "#d4d4d8"
        border.width: 1
    }
}
