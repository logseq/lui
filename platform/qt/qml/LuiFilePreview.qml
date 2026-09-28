import QtQuick

// Wire kind: file-preview — non-rendering node; the owning backend presents a
// native preview of the "path" prop while the node is mounted.
Item {
    required property var node
    readonly property var props: node ? node.properties : ({})
    visible: false
    implicitWidth: 0
    implicitHeight: 0
}
