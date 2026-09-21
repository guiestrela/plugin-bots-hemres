import QtQuick

Item {
    id: root

    property var bar
    property string moduleName
    property var settings

    implicitWidth: 28
    implicitHeight: bar && bar.barSize ? bar.barSize : 26

    Accessible.role: Accessible.Button
    Accessible.name: qsTr("Hermes Bots")
    Accessible.description: qsTr("Panel-only Hermes bot widget; RPC integration is not available.")

    Text {
        anchors.centerIn: parent
        text: qsTr("HB")
        color: root.bar && root.bar.foreground ? root.bar.foreground : "white"
        font.family: root.bar && root.bar.fontFamily ? root.bar.fontFamily : "monospace"
        font.pixelSize: 11
        font.bold: true
        Accessible.ignored: true
    }

    // Deliberately inert until a verified panel and RPC transport exist.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
    }
}
