import QtQuick
import QtQuick.Controls
import "LuiStyle.js" as Style

// Wire kind: select — picker trigger; pressing emits press so the runtime
// can attach a dropdown-menu child.
Button {
    id: select
    required property var node
    readonly property var props: node ? node.properties : ({})

    enabled: props["enabled"] !== false
    implicitWidth: Math.max(160, label.implicitWidth + 40)
    implicitHeight: 34

    contentItem: Item {
        implicitWidth: label.implicitWidth + 40
        implicitHeight: label.implicitHeight
        Text {
            id: label
            anchors {
                left: parent.left
                leftMargin: 10
                right: parent.right
                rightMargin: 30
                verticalCenter: parent.verticalCenter
            }
            text: Style.str(select.props, "text", "") !== ""
                  ? Style.str(select.props, "text", "")
                  : Style.str(select.props, "placeholder", "")
            color: Style.str(select.props, "text", "") !== ""
                   ? Style.color(select.props["foreground"], select.palette.text)
                   : select.palette.placeholderText
            font.pixelSize: 14
            elide: Text.ElideRight
        }
    }

    indicator: Text {
        text: "▾"
        color: select.palette.mid
        anchors {
            right: parent.right
            rightMargin: 8
            verticalCenter: parent.verticalCenter
        }
    }



    onClicked: node.press()
}
