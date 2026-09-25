import QtQuick
import QtQuick.Controls
import "LuiStyle.js" as Style

// Wire kind: textarea — multiline text input.
ScrollView {
    id: view
    required property var node
    readonly property var props: node ? node.properties : ({})

    implicitWidth: 260
    implicitHeight: 96
    clip: true

    TextArea {
        id: area
        placeholderText: Style.str(view.props, "placeholder", "")
        enabled: view.props["enabled"] !== false
        color: Style.color(view.props["foreground"], palette.text)
        wrapMode: TextArea.Wrap
        Component.onCompleted: {
            if (view.props["autofocus"] === true) forceActiveFocus()
            sync()
        }

        property string wireText: Style.str(view.props, "text", "")
        property bool updating: false
        function sync() {
            if (text !== wireText) {
                updating = true
                text = wireText
                updating = false
            }
        }
        onWireTextChanged: sync()
        onTextChanged: if (!updating) view.node.textChanged(text)

        Keys.onReturnPressed: function(event) {
            if (view.props["submit-on-enter"] === true &&
                    !(event.modifiers & Qt.ShiftModifier)) {
                view.node.submit()
                event.accepted = true
            }
        }
        Keys.onEnterPressed: function(event) {
            if (view.props["submit-on-enter"] === true &&
                    !(event.modifiers & Qt.ShiftModifier)) {
                view.node.submit()
                event.accepted = true
            }
        }
    }

    background: Rectangle {
        color: area.enabled ? view.palette.base : view.palette.alternateBase
        border.color: area.activeFocus ? view.palette.highlight
                                       : view.palette.mid
        border.width: 1
        radius: 2
    }
}
