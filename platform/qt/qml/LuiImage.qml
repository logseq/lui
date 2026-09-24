import QtQuick
import "LuiStyle.js" as Style

// Wire kind: image — raster image; opaque sources are resolved through the
// "image://lui/image/<key>" provider the backend installs.
Image {
    required property var node
    readonly property var props: node ? node.properties : ({})

    source: {
        var src = Style.str(props, "source", "")
        if (src === "") return ""
        if (src.startsWith("http") || src.startsWith("file:") ||
                src.startsWith("image:") || src.startsWith("data:"))
            return src
        return "image://lui/image/" + src
    }
    readonly property int imageWidth: Style.num(props, "width", 0)
    readonly property int imageHeight: Style.num(props, "height", 0)
    implicitWidth: imageWidth > 0 ? imageWidth : 48
    implicitHeight: imageHeight > 0 ? imageHeight : 48
    fillMode: Image.PreserveAspectFit
    asynchronous: true
}
