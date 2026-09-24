import QtQuick
import "LuiStyle.js" as Style

// Wire kind: media-surface — host-presented frames (video/camera) looked up
// by the integer "surface" id through the "image://lui/surface/<id>" provider.
Item {
    id: wrapper
    required property var node
    readonly property var props: node ? node.properties : ({})

    readonly property int surfaceId: Style.num(props, "surface", 0)
    readonly property int surfaceWidth: Style.num(props, "width", 0)
    readonly property int surfaceHeight: Style.num(props, "height", 0)

    // Image.implicitWidth/Height are read-only, so the wrapper owns the
    // implicit size.
    implicitWidth: surfaceWidth > 0 ? surfaceWidth : 320
    implicitHeight: surfaceHeight > 0 ? surfaceHeight : 180

    Image {
        anchors.fill: parent
        source: wrapper.surfaceId > 0
                ? "image://lui/surface/" + wrapper.surfaceId : ""
        fillMode: Image.PreserveAspectFit
        cache: false
    }
}
