import QtQuick
import "LuiStyle.js" as Style

// Wire kind: avatar — circular registered image ("image" id) with fallback
// initials from "text".
Rectangle {
    id: avatar
    required property var node
    readonly property var props: node ? node.properties : ({})

    readonly property int imageId: Style.num(props, "image", 0)
    readonly property int avatarSize: Style.num(props, "size", 40)
    implicitWidth: avatarSize
    implicitHeight: avatarSize
    radius: avatarSize / 2
    color: "#e4e4e7"
    clip: true

    Image {
        anchors.fill: parent
        // node.revision versions the URL so re-registered pixels reload.
        source: avatar.imageId > 0
                ? "image://lui/image/" + avatar.imageId +
                  "?v=" + (avatar.node ? avatar.node.revision : 0) : ""
        fillMode: Image.PreserveAspectCrop
        visible: avatar.imageId > 0
    }

    Text {
        anchors.centerIn: parent
        text: Style.str(avatar.props, "text", "")
        color: "#52525b"
        font.pixelSize: Math.max(10, avatar.avatarSize * 0.38)
        visible: avatar.imageId <= 0
    }
}
