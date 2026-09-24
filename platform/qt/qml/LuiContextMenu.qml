import QtQuick

// Wire kind: context-menu — rendered by the parent's LuiNodeView chrome
// (right-click / long-press Menu). This stub exists so the dispatcher can
// resolve the kind; it paints nothing itself.
Item {
    required property var node
    implicitWidth: 0
    implicitHeight: 0
}
