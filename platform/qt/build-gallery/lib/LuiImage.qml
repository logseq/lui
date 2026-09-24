import QtQuick
import "LuiStyle.js" as Style

// Wire kind: image — registered pixels looked up by the integer "image" id
// through the "image://lui/image/<id>" provider the backend installs;
// source-x/y/width/height crop the source rect.
Item {
    id: wrapper
    required property var node
    readonly property var props: node ? node.properties : ({})

    readonly property int imageId: Style.num(props, "image", 0)
    readonly property int imageWidth: Style.num(props, "width", 0)
    readonly property int imageHeight: Style.num(props, "height", 0)
    readonly property bool hasCrop:
        props["source-x"] !== undefined && props["source-y"] !== undefined &&
        props["source-width"] !== undefined &&
        props["source-height"] !== undefined

    // Image.implicitWidth/Height are read-only, so the wrapper owns the
    // implicit size.
    implicitWidth: imageWidth > 0 ? imageWidth : 48
    implicitHeight: imageHeight > 0 ? imageHeight : 48

    Image {
        anchors.fill: parent
        source: wrapper.imageId > 0
                ? "image://lui/image/" + wrapper.imageId : ""
        sourceClipRect: wrapper.hasCrop
            ? Qt.rect(Style.num(wrapper.props, "source-x", 0),
                      Style.num(wrapper.props, "source-y", 0),
                      Style.num(wrapper.props, "source-width", 0),
                      Style.num(wrapper.props, "source-height", 0))
            : undefined
        fillMode: Image.PreserveAspectFit
        asynchronous: true
    }
}
