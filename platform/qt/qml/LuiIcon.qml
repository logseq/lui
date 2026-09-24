import QtQuick
import "LuiStyle.js" as Style

// Wire kind: icon — named SVG glyph.
Image {
    required property var node
    readonly property var props: node ? node.properties : ({})

    source: Style.iconSource(Style.str(props, "icon", ""))
    readonly property int iconSize: Style.num(props, "size", 16)
    implicitWidth: iconSize
    implicitHeight: iconSize
    sourceSize.width: iconSize
    sourceSize.height: iconSize
    fillMode: Image.PreserveAspectFit
}
