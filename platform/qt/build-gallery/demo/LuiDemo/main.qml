import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Lui

ApplicationWindow {
    id: window
    visible: true
    width: 480
    height: 640
    title: "LUI — Qt/QML todos demo"
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

        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: true
            active: luiBackend.rootNode !== null
            sourceComponent: LuiNodeView {
                node: luiBackend.rootNode
                anchors.fill: parent
            }
        }
    }
}
