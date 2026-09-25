import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "LuiStyle.js" as Style

// Wire kind: search-field — search input with a leading glyph.
TextField {
    id: field
    required property var node
    readonly property var props: node ? node.properties : ({})

    placeholderText: Style.str(props, "placeholder", "")
    enabled: props["enabled"] !== false
    color: Style.nodeColor(node, props["foreground"], palette.text)
    implicitWidth: 220
    leftPadding: 30
    Component.onCompleted: {
        if (props["autofocus"] === true) forceActiveFocus()
        sync()
    }

    Image {
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 14
        height: 14
        source: "icons/search.svg"
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

    implicitHeight: 32
    background.implicitHeight: 32
}
