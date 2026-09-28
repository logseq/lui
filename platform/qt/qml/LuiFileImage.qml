import QtQuick
import "LuiStyle.js" as Style

// Wire kind: file-image — loads a local file path (or file:// URL) through
// Qt's image pipeline, downsampled to "max-pixel-size" (default 1024).
Item {
    id: wrapper
    required property var node
    readonly property var props: node ? node.properties : ({})

    readonly property string path: Style.str(props, "path", "")
    readonly property int maxPixelSize:
        Style.num(props, "max-pixel-size", 1024)

    implicitWidth: Style.num(props, "width", 48)
    implicitHeight: Style.num(props, "height", 48)

    Image {
        anchors.fill: parent
        source: wrapper.path.indexOf("file://") === 0
                ? wrapper.path : "file://" + wrapper.path
        sourceSize.width: wrapper.maxPixelSize
        sourceSize.height: wrapper.maxPixelSize
        fillMode: Image.PreserveAspectFit
        asynchronous: true
    }

    TapHandler {
        enabled: wrapper.props["press-enabled"] === true
        onTapped: {
            if (wrapper.node && wrapper.node.backend)
                wrapper.node.backend.performPress(wrapper.node.id)
        }
    }
}
