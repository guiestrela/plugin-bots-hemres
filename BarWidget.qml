import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import "ui"

BarWidget {
    id: root
    moduleName: "io.github.guiestrela.hermes-bots"

    property var shell: null
    // Compatibility injection point; transport ownership is the persistent service.
    property var adapter: null
    property var service: null
    property var profiles: service ? service.profiles : []
    property string adapterState: service ? service.viewState : "error"
    property string adapterError: service ? service.error : I18n.text("Hermes service not loaded.", "Serviço Hermes não carregado.")
    property string selectedProfile: service ? service.selectedProfile : ""

    function refreshService() {
        if (root.shell && root.shell.serviceFor)
            root.service = root.shell.serviceFor("io.github.guiestrela.hermes-bots")
    }

    Component.onCompleted: refreshService()
    onServiceChanged: {
        if (panelContent)
            panelContent.service = root.service
    }

    property bool panelOpen: false
    property string tooltipText: I18n.text("Hermes Bots — open profiles panel", "Bots Hermes — abrir painel de perfis")

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    WidgetButton {
        id: button
        bar: root.bar
        text: "♟"
        labelVisible: false
        tooltipText: root.tooltipText
        onPressed: function(buttonCode) {
            if (buttonCode === Qt.LeftButton)
                root.panelOpen = !root.panelOpen
        }
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
