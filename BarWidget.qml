import QtQuick 2.15
import QtQuick.Controls 2.15
import "ui"

Item {
    id: root

    property var bar
    property string moduleName
    property var settings

    property var shell: null
    // Compatibility injection point; transport ownership is the persistent service.
    property var adapter: null
    property var service: null
    property var profiles: service ? service.profiles : []
    property string adapterState: service ? service.viewState : "error"
    property string adapterError: service ? service.error : qsTr("Serviço Hermes não carregado.")
    property string selectedProfile: service ? service.selectedProfile : ""
    property bool panelOpen: false

    function refreshService() {
        if (root.shell && root.shell.serviceFor)
            root.service = root.shell.serviceFor("io.github.guiestrela.hermes-bots")
    }

    Component.onCompleted: refreshService()
    onServiceChanged: {
        if (panelContent)
            panelContent.service = root.service
    }

    implicitWidth: 30
    implicitHeight: bar && bar.barSize ? bar.barSize : 26

    Accessible.role: Accessible.Button
    Accessible.name: qsTr("Bots Hermes")
    Accessible.description: qsTr("Abrir painel de perfis Hermes")
    Accessible.onPressAction: panelOpen = !panelOpen

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: mouse.containsMouse ? Qt.alpha(root.bar && root.bar.foreground ? root.bar.foreground : "white", 0.18) : "transparent"

        Text {
            anchors.centerIn: parent
            text: qsTr("♟")
            color: root.bar && root.bar.foreground ? root.bar.foreground : "white"
            font.family: root.bar && root.bar.fontFamily ? root.bar.fontFamily : "monospace"
            font.pixelSize: 15
            Accessible.ignored: true
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        accessibleName: qsTr("Abrir painel de bots Hermes")
        onClicked: root.panelOpen = !root.panelOpen
    }

    Popup {
        id: panelPopup
        parent: root
        x: 0
        y: root.height + 4
        width: 360
        height: Math.min(560, panelContent.implicitHeight + OmarchyTokens.spacing * 2)
        padding: 0
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        visible: root.panelOpen
        onClosed: root.panelOpen = false

        background: Rectangle {
            color: OmarchyTokens.popupBackground
            border.color: OmarchyTokens.popupBorder
            border.width: 1
            radius: OmarchyTokens.cornerRadius
        }

        BotPanel {
            id: panelContent
            anchors.fill: parent
            service: root.service
            profiles: root.profiles
            selectedProfile: root.selectedProfile
            viewState: root.adapterState
            errorMessage: root.adapterError
        }
    }
}
