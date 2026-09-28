import QtQuick

// Wire kind: overlay — children after the first float over the first child
// without affecting its layout. Each overlay child positions itself by its
// own `alignment` property, falling back to the overlay's (default center).
Item {
    id: overlay
    required property var node
    readonly property var props: node ? node.properties : ({})

    implicitWidth: rep.itemAt(0) ? rep.itemAt(0).implicitWidth : 0
    implicitHeight: rep.itemAt(0) ? rep.itemAt(0).implicitHeight : 0

    Repeater {
        id: rep
        model: overlay.node ? overlay.node.children : []
        delegate: LuiNodeView {
            required property var modelData
            required property int index
            node: modelData

            readonly property bool _isBase: index === 0
            // Own `alignment` hint, falling back to the overlay's.
            readonly property string _align: {
                var p = node ? node.properties : null
                return (p && p.alignment) || overlay.props.alignment ||
                       "center"
            }
            readonly property bool _top: !_isBase &&
                (_align === "top-leading" || _align === "top" ||
                 _align === "top-trailing")
            readonly property bool _bottom: !_isBase &&
                (_align === "bottom-leading" || _align === "bottom" ||
                 _align === "bottom-trailing")
            readonly property bool _leading: !_isBase &&
                (_align === "top-leading" || _align === "leading" ||
                 _align === "bottom-leading")
            readonly property bool _trailing: !_isBase &&
                (_align === "top-trailing" || _align === "trailing" ||
                 _align === "bottom-trailing")

            // Bound anchors re-evaluate when `alignment` changes;
            // `undefined` clears the anchor. The base child fills.
            anchors.top: _isBase || _top ? overlay.top : undefined
            anchors.bottom: _isBase || _bottom ? overlay.bottom : undefined
            anchors.left: _isBase || _leading ? overlay.left : undefined
            anchors.right: _isBase || _trailing ? overlay.right : undefined
            anchors.horizontalCenter: !_isBase && !_leading && !_trailing
                                      ? overlay.horizontalCenter : undefined
            anchors.verticalCenter: !_isBase && !_top && !_bottom
                                    ? overlay.verticalCenter : undefined
        }
    }
}
