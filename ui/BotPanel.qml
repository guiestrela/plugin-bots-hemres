import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Quickshell.Io

Item {
    id: panel

    // Persistent read-only gateway service supplied by BarWidget.
    property var service: null
    property var adapter: null
    property var profiles: []
    property string viewState: "error"
    property string errorMessage: I18n.text("Adapter not connected.", "Adaptador não conectado.")
    property string selectedProfile: ""
    property string gatewayUrl: ""
    property string pythonExecutable: "/home/guiestrela/.hermes/hermes-agent/venv/bin/python3"
    property string delegationState: "idle"
    property string delegationMessage: ""
    signal refreshRequested()
    property string taskText: ""

    implicitWidth: 360
    implicitHeight: 560

    function profileValue(profile, snake, camel, fallback) {
        if (!profile)
            return fallback
        if (profile[snake] !== undefined && profile[snake] !== null && String(profile[snake]).trim().length > 0)
            return String(profile[snake])
        if (profile[camel] !== undefined && profile[camel] !== null && String(profile[camel]).trim().length > 0)
            return String(profile[camel])
        return fallback
    }

    function fallbackAvatarShape(index) {
        var shapes = ["squircle", "circle", "hex", "cloud", "teardrop", "tablet"]
        return shapes[index % shapes.length]
    }

    function fallbackAvatarColor(index) {
        var palette = ["#c9dbcb", "#d94aa7", "#84d957", "#c9dbcb", "#4bc7e7", "#8f4ee8"]
        return palette[index % palette.length]
    }

    function normalizedAvatarShape(shape, index) {
        var value = String(shape || "")
        if (value.indexOf("::") >= 0)
            value = value.split("::").pop()
        var allowed = ["squircle", "circle", "hex", "cloud", "teardrop", "tablet", "blob"]
        return allowed.indexOf(value) >= 0 ? value : fallbackAvatarShape(index)
    }

    function displayNameFor(profile, fallback) {
        var name = String(profileValue(profile, "name", "id", "")).toLowerCase()
        if (name === "desktop-dev")
            return I18n.text("Desktop Dev", "Desktop Dev")
        return fallback
    }

    function referenceAvatar(profile, index) {
        var name = String(profileValue(profile, "name", "id", "")).toLowerCase()
        var styles = {
            "default": {shape: "tablet", color: "#8f4ee8"},
            "cto": {shape: "blob", color: "#8f4ee8"},
            "backend": {shape: "hex", color: "#c9dbcb"},
            "frontend": {shape: "circle", color: "#d94aa7"},
            "assistente-sistema": {shape: "hex", color: "#84d957"},
            "pentester": {shape: "teardrop", color: "#4bc7e7"},
            "desktop-dev": {shape: "cloud", color: "#e8a84e"}
        }
        return styles[name] || {shape: fallbackAvatarShape(index), color: fallbackAvatarColor(index)}
    }

    function rebuildProfiles() {
        profileModel.clear()
        for (var i = 0; i < profiles.length; i++) {
            var profile = profiles[i]
            var name = profileValue(profile, "name", "id", "profile-" + i)
            var displayName = displayNameFor(profile, profileValue(profile, "display_name", "displayName", name))
            var avatar = referenceAvatar(profile, i)
            profileModel.append({
                profileName: name,
                displayName: displayName,
                description: profileValue(profile, "description", "description", I18n.text("Description not provided", "Descrição não informada")),
                hasAvatar: Boolean(profile && (profile.has_avatar || profile.hasAvatar)),
                avatarSource: profileValue(profile, "avatar", "avatarSource", ""),
                avatarShape: avatar.shape,
                avatarColor: avatar.color
            })
        }
        if (profileModel.count === 0)
            selectedProfile = ""
        else if (selectedProfile.length === 0 || !profileExists(selectedProfile))
            selectedProfile = profileModel.get(0).profileName
    }

    function profileExists(profileName) {
        for (var i = 0; i < profileModel.count; i++) {
            if (profileModel.get(i).profileName === profileName)
                return true
        }
        return false
    }

    onProfilesChanged: rebuildProfiles()
    Component.onCompleted: rebuildProfiles()

    Connections {
        target: panel.service
        function onAvatarSourcesChanged() { panel.rebuildProfiles() }
    }

    ListModel { id: profileModel }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: OmarchyTokens.spacing
        spacing: OmarchyTokens.compactSpacing

        RowLayout {
            Layout.fillWidth: true
            Label {
                text: I18n.text("Hermes Bots", "Bots Hermes")
                textFormat: Text.PlainText
                color: OmarchyTokens.text
                font.bold: true
                font.pixelSize: 18
                Layout.fillWidth: true
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            Button {
                text: I18n.text("Refresh", "Atualizar")
                enabled: panel.viewState !== "loading"
                onClicked: panel.refreshRequested()
                Accessible.name: I18n.text("Refresh bot list", "Atualizar lista de bots")
            }
        }
        Label {
            text: panel.viewState === "loading" ? I18n.text("Loading profiles…", "Carregando perfis…")
                  : panel.viewState === "error" ? panel.errorMessage
                  : panel.viewState === "empty" ? I18n.text("No profiles available", "Nenhum perfil disponível")
                  : I18n.text("Select a profile to see its details", "Selecione um perfil para ver seus detalhes")
            textFormat: Text.PlainText
            color: panel.viewState === "error" ? OmarchyTokens.urgent : OmarchyTokens.mutedText
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Accessible.role: panel.viewState === "error" ? Accessible.Alert : Accessible.StaticText
            Accessible.name: text
        }

        BusyIndicator {
            visible: panel.viewState === "loading"
            running: visible
            Layout.alignment: Qt.AlignHCenter
            Accessible.name: I18n.text("Loading profiles", "Carregando perfis")
        }
        Label {
            visible: panel.viewState === "empty"
            text: I18n.text("The adapter returned an empty list.", "O adaptador retornou uma lista vazia.")
            textFormat: Text.PlainText
            color: OmarchyTokens.mutedText
            Layout.alignment: Qt.AlignHCenter
            Accessible.name: text
        }

        ListView {
            id: profileList
            visible: panel.viewState === "ready" && profileModel.count > 0
            model: profileModel
            clip: true
            spacing: OmarchyTokens.compactSpacing
            focus: true
            keyNavigationEnabled: true
            Layout.fillWidth: true
            // Reserve complete rows; larger rosters scroll in a bounded area.
            Layout.preferredHeight: 340
            Layout.fillHeight: false
            Accessible.role: Accessible.List
            Accessible.name: I18n.text("Hermes profiles", "Perfis Hermes")
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }
            delegate: BotRow {
                width: profileList.width
                botId: model.profileName
                botName: model.displayName
                botRole: model.description
                avatarValid: model.hasAvatar || Boolean(panel.service && panel.service.avatarSources
                                                       && panel.service.avatarSources[model.profileName])
                avatarSource: panel.service && panel.service.avatarSources
                              && panel.service.avatarSources[model.profileName]
                              ? panel.service.avatarSources[model.profileName] : model.avatarSource
                avatarShape: model.avatarShape
                avatarFill: model.avatarColor
                availability: I18n.text("loaded", "carregado")
                selected: model.profileName === panel.selectedProfile
                onClicked: {
                    panel.selectedProfile = model.profileName
                    if (panel.service && panel.service.fetchAvatar)
                        panel.service.fetchAvatar(model.profileName)
                }
            }
        }

        GroupBox {
            visible: panel.viewState === "ready" && profileModel.count > 0
            title: I18n.text("Delegate task", "Delegar tarefa")
            Layout.fillWidth: true
            enabled: true
            implicitHeight: delegateLayout.implicitHeight + 48
            ColumnLayout {
                id: delegateLayout
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                TextArea {
                    text: panel.taskText
                    onTextChanged: panel.taskText = text
                    placeholderText: I18n.text("Describe the task…", "Descreva a tarefa…")
                    readOnly: false
                    enabled: true
                    selectByMouse: true
                    persistentSelection: true
                    Layout.fillWidth: true
                    Layout.preferredHeight: 58
                    Accessible.name: qsTr("Texto da delegação desabilitado")
                }
                Button {
                    text: panel.delegationState === "running"
                          ? I18n.text("Sending…", "Enviando…")
                          : I18n.text("Delegate", "Delegar")
                    enabled: panel.selectedProfile.length > 0 && panel.taskText.trim().length > 0
                              && panel.delegationState !== "running"
                    Accessible.name: I18n.text("Delegate task", "Delegar tarefa")
                    Layout.alignment: Qt.AlignRight
                    onClicked: panel.delegate()
                }
                Label {
                    text: panel.delegationMessage
                    visible: text.length > 0
                    textFormat: Text.PlainText
                    color: OmarchyTokens.mutedText
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }
    }

    function delegate() {
        delegationState = "running"
        delegationMessage = I18n.text("Creating session and sending task…", "Criando sessão e enviando tarefa…")
        delegateRequest.command = [pythonExecutable, delegateFile]
        delegateRequest.running = true
    }

    readonly property string delegateFile: decodeURIComponent(Qt.resolvedUrl("../scripts/hermes_delegate.py").toString().replace(/^file:\/\//, ""))

    Process {
        id: delegateRequest
        stdinEnabled: true
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var response = JSON.parse(text)
                    delegationState = response.ok ? "submitted" : "error"
                    delegationMessage = response.ok
                        ? I18n.text("Sent to bot; completion not yet confirmed.", "Enviado ao bot; conclusão ainda não confirmada.")
                        : I18n.text("Not sent: " + response.error, "Não enviado: " + response.error)
                    if (response.ok)
                        taskText = ""
                } catch (error) {
                    delegationState = "error"
                    delegationMessage = I18n.text("Invalid delegation response.", "Resposta de delegação inválida.")
                }
            }
        }
        onStarted: write(JSON.stringify({url: panel.gatewayUrl, profile: panel.selectedProfile, text: panel.taskText}) + "\n")
        onExited: if (exitCode !== 0 && panel.delegationState === "running") {
            panel.delegationState = "error"
            panel.delegationMessage = I18n.text("Gateway unavailable.", "Gateway indisponível.")
        }
    }
}
