import QtQuick
import "LuiStyle.js" as Style

// Wire kind: avatar — circular image with fallback initials.
Rectangle {
    id: avatar
    required property var node
    readonly property var props: node ? node.properties : ({})

    readonly property int avatarSize: Style.num(props, "size", 32)
    implicitWidth: avatarSize
    implicitHeight: avatarSize
    radius: avatarSize / 2
    color: "#e4e4e7"
    clip: true

    Image {
        anchors.fill: parent
        source: {
            var src = Style.str(avatar.props, "source", "")
            if (src === "") return ""
            if (src.startsWith("http") || src.startsWith("file:") ||
                    src.startsWith("image:"))
                return src
            return "image://lui/image/" + src
        }
        fillMode: Image.PreserveAspectCrop
        visible: status === Image.Ready || status === Image.Loading
    }

    Text {
        anchors.centerIn: parent
        text: Style.str(avatar.props, "text", "")
        color: "#52525b"
        font.pixelSize: Math.max(10, avatar.avatarSize * 0.38)
        visible: Style.str(avatar.props, "source", "") === ""
    }
}
