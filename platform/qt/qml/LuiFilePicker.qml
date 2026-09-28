import QtQuick
import QtQuick.Layouts

// Wire kind: file-picker — non-visual element; the Qt backend does not
// present a native file dialog. Per the element contract a request the
// backend cannot serve is answered with `dismiss`. Children (if any)
// render inline.
Item {
    id: picker
    required property var node
    readonly property var props: node ? node.properties : ({})

    // Re-evaluates on every node change; `onPendingRequestChanged` fires
    // only when the request token itself changes (a re-sent identical
    // token is not a new request).
    readonly property var pendingRequest: props["request"]
    readonly property var completionToken: props["completion"]

    function reportUnserved() {
        if (!node) return
        if (pendingRequest === undefined || pendingRequest === null) return
        // A token equal to `completion` was already acknowledged.
        if (pendingRequest === completionToken) return
        node.dismiss()
    }

    onPendingRequestChanged: reportUnserved()
    Component.onCompleted: reportUnserved()

    implicitWidth: col.implicitWidth
    implicitHeight: col.implicitHeight

    ColumnLayout {
        id: col
        spacing: 0
        Repeater {
            model: picker.node ? picker.node.children : []
            delegate: LuiNodeView {
                required property var modelData
                node: modelData
            }
        }
    }
}
