import QtQuick
import QtQuick.Controls
import "LuiStyle.js" as Style

// Wire kind: combobox — editable text input whose arrow opens the picker
// (press event so the runtime can attach a dropdown-menu child).
TextField {
    id: field
    required property var node
    readonly property var props: node ? node.properties : ({})

    placeholderText: Style.str(props, "placeholder", "")
    enabled: props["enabled"] !== false
    color: Style.color(props["foreground"], palette.text)
    implicitWidth: 200
    rightPadding: 28
    Component.onCompleted: sync()

    Text {
        text: "▾"
        color: palette.mid
        anchors {
            right: parent.right
            rightMargin: 8
            verticalCenter: parent.verticalCenter
        }
    }
    MouseArea {
        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
        }
        width: 28
        onClicked: field.node.press()
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
    onAccepted: node.press()

    implicitHeight: 34
    background.implicitHeight: 34
}
