import QtQuick
import "LuiStyle.js" as Style

// Wire kind: media-surface — host-presented frames (video/camera) delivered
// through the "image://lui/surface/<id>" provider.
Image {
    required property var node
    readonly property var props: node ? node.properties : ({})

    source: node ? "image://lui/surface/" + node.nodeId : ""
    readonly property int surfaceWidth: Style.num(props, "width", 0)
    readonly property int surfaceHeight: Style.num(props, "height", 0)
    implicitWidth: surfaceWidth > 0 ? surfaceWidth : 320
    implicitHeight: surfaceHeight > 0 ? surfaceHeight : 180
    fillMode: Image.PreserveAspectFit
    cache: false
}
