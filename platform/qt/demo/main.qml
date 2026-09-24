import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Lui

ApplicationWindow {
    id: window
    visible: true
    width: 480
    height: 640
    title: "LUI — Qt/QML " + luiAppName + " demo"
    color: "#ffffff"

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            visible: luiBackend.lastError !== ""
            Layout.fillWidth: true
            implicitHeight: errorLabel.implicitHeight + 12
            color: "#fee2e2"
            Text {
                id: errorLabel
                anchors.centerIn: parent
                width: parent.width - 16
                text: luiBackend.lastError
                color: "#991b1b"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }

        // The window scrolls apps whose root content is taller than the
        // viewport (e.g. the components gallery is a ~50-section column),
        // matching the browser/SwiftUI hosts where the page scrolls.
        ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Loader {
                active: luiBackend.rootNode !== null
                width: scroll.availableWidth
                sourceComponent: LuiNodeView {
                    node: luiBackend.rootNode
                    width: parent.width
                    height: Math.max(implicitHeight,
                                     scroll.availableHeight)
                }
            }
        }
    }
}
