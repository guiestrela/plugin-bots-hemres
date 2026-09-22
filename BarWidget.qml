import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "ui"

BarWidget {
    id: root
    moduleName: "io.github.guiestrela.hermes-bots"

    property var shell: null
    // Compatibility injection point; transport ownership is the persistent service.
    property var adapter: null
    property var service: null
    property var settings: null
    property string pluginDir: ""
    property string gatewayUrl: settings && settings.gatewayUrl ? String(settings.gatewayUrl) : ""
    property string pythonExecutable: settings && settings.pythonExecutable ? String(settings.pythonExecutable) : "/home/guiestrela/.hermes/hermes-agent/venv/bin/python3"
    property var profiles: rosterProfiles
    property string adapterState: rosterLoading ? "loading" : rosterError.length > 0 ? "error" : rosterProfiles.length > 0 ? "ready" : "empty"
    property string adapterError: rosterError
    property string selectedProfile: ""
    property var rosterProfiles: []
    property bool rosterLoading: false
    property string rosterError: ""
    // Surface harnesses inject synthetic fixtures; a live local gateway must
    // not overwrite them with real profiles during component startup.
    property bool autoRefreshRoster: true

    function refreshService() {
        if (root.shell && root.shell.serviceFor)
            root.service = root.shell.serviceFor("io.github.guiestrela.hermes-bots")
    }

    function refreshRoster() {
        if (rosterLoading)
            return
        rosterLoading = true
        rosterError = ""
        rosterRequest.command = [pythonExecutable, helperFile]
        if (gatewayUrl.length > 0)
            rosterRequest.command.push("--url", gatewayUrl)
        rosterRequest.running = true
    }

    function acceptRoster(raw) {
        try {
            var response = JSON.parse(raw)
            if (!response.ok) {
                if (response.error === "gateway_unavailable")
                    rosterError = I18n.text("Hermes gateway unavailable.", "Gateway Hermes indisponível.")
                else if (response.error === "configuration_required")
                    rosterError = I18n.text("Hermes gateway is not configured.", "Gateway Hermes não configurado.")
                else
                    rosterError = I18n.text("Unable to load Hermes profiles.", "Não foi possível carregar os perfis Hermes.")
                return
            }
            if (response.kind === "profiles" && Array.isArray(response.profiles)) {
                if (response.gateway_url)
                    gatewayUrl = String(response.gateway_url)
                rosterProfiles = response.profiles
                return
            }
            rosterError = I18n.text("Unable to load Hermes profiles.", "Não foi possível carregar os perfis Hermes.")
        } catch (error) {
            rosterError = I18n.text("Invalid Hermes response.", "Resposta Hermes inválida.")
        }
    }

    Component.onCompleted: {
        refreshService()
        if (autoRefreshRoster)
            Qt.callLater(refreshRoster)
    }
    onServiceChanged: {
        if (panelContent)
            panelContent.service = root.service
    }

    property bool panelOpen: false
    property string tooltipText: I18n.text("Hermes Bots — open profiles panel", "Bots Hermes — abrir painel de bots")
    onPanelOpenChanged: {
        if (autoRefreshRoster && panelOpen && (rosterProfiles.length === 0 || rosterError.length > 0))
            refreshRoster()
        if (panelOpen && panelContent.selectedProfile.length > 0)
            Qt.callLater(function() { panelContent.focusTaskInput() })
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    WidgetButton {
        id: button
        bar: root.bar
        text: ""
        hasVisualContent: true
        fixedWidth: vertical ? -1 : Style.bar.iconSlot
        fixedHeight: vertical ? Style.bar.iconSlot : -1
        labelVisible: false
        tooltipText: root.tooltipText
        onPressed: function(buttonCode) {
            if (buttonCode === Qt.LeftButton)
                root.panelOpen = !root.panelOpen
        }

        Avatar {
            anchors.centerIn: parent
            width: Style.bar.iconCanvas
            height: Style.bar.iconCanvas
            shape: "squircle"
            outlined: true
            fill: root.bar ? root.bar.barForeground : "#cdd6f4"
            eyeColor: root.bar ? root.bar.barForeground : "#cdd6f4"
            face: "neutral"
            animate: false
            Accessible.name: I18n.text("Hermes bot", "Bot Hermes")
        }
    }

    readonly property string helperFile: decodeURIComponent(Qt.resolvedUrl("scripts/hermes_profiles.py").toString().replace(/^file:\/\//, ""))

    Process {
        id: rosterRequest
        command: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.acceptRoster(text)
        }
        onExited: {
            root.rosterLoading = false
            if (exitCode !== 0 && root.rosterError.length === 0)
                root.rosterError = I18n.text("Hermes gateway unavailable.", "Gateway Hermes indisponível.")
        }
    }

    // The host coordinates owners through close(); PopupCard supplies its
    // own PopupWindow, anchor geometry and outside-click dismissal.
    function close() { root.panelOpen = false }

    PopupCard {
        id: panelPopup
        anchorItem: button
        bar: root.bar
        owner: root
        open: root.panelOpen
        padding: 0
        contentWidth: fittedContentWidth(440)
        contentHeight: fittedContentHeight(panelContent.implicitHeight, 620)

        BotPanel {
            id: panelContent
            anchors.fill: parent
            focus: root.panelOpen
            Keys.onEscapePressed: root.close()
            service: root.service
            profiles: root.profiles
            selectedProfile: root.selectedProfile
            viewState: root.adapterState
            errorMessage: root.adapterError
            gatewayUrl: root.gatewayUrl
            pythonExecutable: root.pythonExecutable
            onRefreshRequested: root.refreshRoster()
        }
    }
}
