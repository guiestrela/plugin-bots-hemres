import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Quickshell.Io
import qs.Commons
import qs.Ui
import "."

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
    property var taskDrafts: ({})
    property var botResponses: ({})
    property string pendingProfile: ""

    function draftFor(profile) {
        return profile && taskDrafts[profile] !== undefined ? String(taskDrafts[profile]) : ""
    }

    function responseFor(profile) {
        return profile && botResponses[profile] !== undefined ? String(botResponses[profile]) : ""
    }

    function setDraft(profile, value) {
        if (!profile)
            return
        var next = Object.assign({}, taskDrafts)
        next[profile] = value
        taskDrafts = next
        if (profile === selectedProfile)
            taskText = value
    }

    function setResponse(profile, value) {
        if (!profile)
            return
        var next = Object.assign({}, botResponses)
        next[profile] = value
        botResponses = next
    }

    function clearResponse(profile) {
        if (!profile)
            return
        var next = Object.assign({}, botResponses)
        delete next[profile]
        botResponses = next
        if (pendingProfile === profile && delegationState !== "running") {
            delegationMessage = ""
            pendingProfile = ""
            delegationState = "idle"
        }
    }

    function focusTaskInput() {
        // The task editor is owned by the selected ListView delegate.
    }

    implicitWidth: 360
    implicitHeight: selectedProfile.length > 0 ? 620 : 490

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
        var aliases = {hexagon: "hex", blobatar: "blob"}
        if (aliases[value])
            value = aliases[value]
        var allowed = ["circle", "egg", "capsule", "cylinder", "tablet", "squircle", "hex",
                       "gem", "crystal", "wedge", "shield", "dome", "arch", "bean", "pebble",
                       "cloud", "teardrop", "leaf", "group", "blob"]
        return allowed.indexOf(value) >= 0 ? value : fallbackAvatarShape(index)
    }

    function metadataAvatar(profile, index) {
        var meta = profile && profile.ui_meta && profile.ui_meta["hermes-bots"]
        if (meta && meta.custom === true && meta.shape)
            return {
                shape: normalizedAvatarShape(meta.shape, index),
                color: String(meta.color || fallbackAvatarColor(index))
            }
        return null
    }

    function displayNameFor(profile, fallback) {
        var name = String(profileValue(profile, "name", "id", "")).toLowerCase()
        if (name === "desktop-dev")
            return I18n.text("Desktop Dev", "Desktop Dev")
        return fallback
    }

    function referenceAvatar(profile, index) {
        var fromHermes = metadataAvatar(profile, index)
        if (fromHermes)
            return fromHermes
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
    }

    function profileExists(profileName) {
        for (var i = 0; i < profileModel.count; i++) {
            if (profileModel.get(i).profileName === profileName)
                return true
        }
        return false
    }

    function delegationProfile() {
        if (selectedProfile.length > 0 && profileExists(selectedProfile))
            return selectedProfile
        return profileModel.count > 0 ? profileModel.get(0).profileName : ""
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
        spacing: Math.max(4, OmarchyTokens.compactSpacing / 2)

        RowLayout {
            Layout.fillWidth: true
            Label {
                text: I18n.text("Hermes Bots", "Bots Hermes")
                textFormat: Text.PlainText
                color: OmarchyTokens.text
                font.family: OmarchyTokens.fontFamily
                font.bold: true
                font.pixelSize: OmarchyTokens.fontSubtitle
                Layout.fillWidth: true
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            BorderSurface {
                id: refreshButton
                property string text: I18n.text("Refresh", "Atualizar")
                property bool isHovered: refreshMouse.containsMouse
                property bool isPressed: refreshMouse.pressed
                signal clicked()
                enabled: panel.viewState !== "loading"
                implicitWidth: refreshLabel.implicitWidth + Style.spacing.controlPaddingX * 2
                implicitHeight: Style.spacing.controlHeight
                radius: Style.cornerRadius
                color: Style.controlFill(activeFocus, isHovered || isPressed, Color.popups.text, Color.accent)
                borderSpec: Border.controlSpec(activeFocus ? "focus" : (isHovered || isPressed ? "hover-cursor" : "normal"), Color.popups.text, Color.accent)
                Text {
                    id: refreshLabel
                    anchors.centerIn: parent
                    text: refreshButton.text
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                }
                MouseArea {
                    id: refreshMouse
                    anchors.fill: parent
                    enabled: refreshButton.enabled
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: refreshButton.clicked()
                }
                Accessible.role: Accessible.Button
                Accessible.name: I18n.text("Refresh bot list", "Atualizar lista de bots")
                onClicked: panel.refreshRequested()
            }
        }
        Label {
            text: panel.viewState === "loading" ? I18n.text("Loading profiles…", "Carregando perfis…")
                  : panel.viewState === "error" ? panel.errorMessage
                  : panel.viewState === "empty" ? I18n.text("No profiles available", "Nenhum perfil disponível")
                  : I18n.text("Select a profile to see its details", "Selecione um perfil para ver seus detalhes")
            textFormat: Text.PlainText
            font.family: OmarchyTokens.fontFamily
            font.pixelSize: OmarchyTokens.fontBodySmall
            color: panel.viewState === "error" ? OmarchyTokens.urgent : OmarchyTokens.mutedText
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Accessible.role: panel.viewState === "error" ? Accessible.Alert : Accessible.StaticText
            Accessible.name: text
        }

        BusyIndicator {
            visible: panel.viewState === "loading"
            running: visible
            Layout.preferredHeight: visible ? implicitHeight : 0
            Layout.minimumHeight: 0
            Layout.maximumHeight: visible ? implicitHeight : 0
            Layout.alignment: Qt.AlignHCenter
            Accessible.name: I18n.text("Loading profiles", "Carregando perfis")
        }
        Label {
            visible: panel.viewState === "empty"
            text: I18n.text("The adapter returned an empty list.", "O adaptador retornou uma lista vazia.")
            textFormat: Text.PlainText
            color: OmarchyTokens.mutedText
            Layout.preferredHeight: visible ? implicitHeight : 0
            Layout.minimumHeight: 0
            Layout.maximumHeight: visible ? implicitHeight : 0
            Layout.alignment: Qt.AlignHCenter
            Accessible.name: text
        }

        ListView {
            id: profileList
            visible: panel.viewState === "ready" && profileModel.count > 0
            model: profileModel
            clip: true
            spacing: OmarchyTokens.compactSpacing
            focus: false
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
            delegate: ColumnLayout {
                width: profileList.width
                spacing: OmarchyTokens.compactSpacing
                BotRow {
                    id: botRow
                    Layout.fillWidth: true
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
                        if (panel.selectedProfile === model.profileName) {
                            panel.selectedProfile = ""
                            panel.taskText = ""
                        } else {
                            panel.selectedProfile = model.profileName
                            panel.taskText = panel.draftFor(model.profileName)
                            if (panel.service && panel.service.fetchAvatar)
                                panel.service.fetchAvatar(model.profileName)
                        }
                    }
                }
                ColumnLayout {
                    visible: panel.selectedProfile === model.profileName
                    Layout.fillWidth: true
                    Layout.leftMargin: OmarchyTokens.spacing
                    Layout.rightMargin: OmarchyTokens.spacing
                    TextArea {
                        id: inlineTaskInput
                        text: panel.draftFor(model.profileName)
                        onTextChanged: {
                            if (text !== panel.draftFor(model.profileName))
                                panel.setDraft(model.profileName, text)
                            if (panel.selectedProfile === model.profileName)
                                panel.taskText = text
                        }
                        activeFocusOnPress: true
                        focus: panel.selectedProfile === model.profileName
                        onFocusChanged: {
                            if (focus)
                                Qt.callLater(function() {
                                    forceActiveFocus()
                                    cursorPosition = length
                                })
                        }
                        placeholderText: I18n.text("Describe the task…", "Descreva a tarefa…")
                        readOnly: panel.delegationState === "running" && panel.pendingProfile === model.profileName
                        enabled: !(panel.delegationState === "running" && panel.pendingProfile === model.profileName)
                        selectByMouse: true
                        persistentSelection: true
                        wrapMode: TextArea.Wrap
                        font.family: OmarchyTokens.fontFamily
                        font.pixelSize: OmarchyTokens.fontBody
                        Layout.fillWidth: true
                        Layout.minimumHeight: 58
                        Layout.maximumHeight: 140
                        Layout.preferredHeight: Math.max(58, Math.min(140, inlineTaskInput.contentHeight))
                        leftPadding: OmarchyTokens.spacing
                        rightPadding: OmarchyTokens.spacing
                        topPadding: OmarchyTokens.compactSpacing
                        bottomPadding: OmarchyTokens.compactSpacing
                        background: BorderSurface {
                            radius: Style.cornerRadius
                            color: Style.controlFill(inlineTaskInput.activeFocus, inlineTaskInput.hovered,
                                                      Color.popups.text, Color.accent)
                            borderSpec: Border.controlSpec(inlineTaskInput.activeFocus ? "focus"
                                                           : (inlineTaskInput.hovered ? "hover-cursor" : "normal"),
                                                           Color.popups.text, Color.accent)
                        }
                        Keys.onPressed: function(event) {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                event.accepted = true
                                panel.selectedProfile = model.profileName
                                panel.delegate()
                            }
                        }
                        Accessible.name: I18n.text("Task for %1", "Tarefa para %1").arg(model.displayName)
                    }
                    ScrollView {
                        id: responseScroll
                        Layout.fillWidth: true
                        Layout.minimumHeight: 72
                        Layout.maximumHeight: 180
                        Layout.preferredHeight: Math.max(72, Math.min(180, responseField.contentHeight))
                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }
                        TextArea {
                        id: responseField
                        text: panel.responseFor(model.profileName)
                        readOnly: true
                        enabled: true
                        wrapMode: TextArea.Wrap
                        placeholderText: I18n.text("Bot response will appear here", "O retorno do bot aparecerá aqui")
                        font.family: OmarchyTokens.fontFamily
                        font.pixelSize: OmarchyTokens.fontBodySmall
                        leftPadding: OmarchyTokens.spacing
                        rightPadding: OmarchyTokens.spacing
                        topPadding: OmarchyTokens.compactSpacing
                        bottomPadding: OmarchyTokens.compactSpacing
                        background: BorderSurface {
                            radius: Style.cornerRadius
                            color: Style.controlFill(responseField.activeFocus, responseField.hovered,
                                                      Color.popups.text, Color.accent)
                            borderSpec: Border.controlSpec(responseField.activeFocus ? "focus"
                                                           : (responseField.hovered ? "hover-cursor" : "normal"),
                                                           Color.popups.text, Color.accent)
                        }
                        Accessible.name: I18n.text("Response from %1", "Retorno de %1").arg(model.displayName)
                    }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: OmarchyTokens.compactSpacing
                    BorderSurface {
                        id: delegateButton
                        property bool isSending: panel.delegationState === "running" && panel.pendingProfile === model.profileName
                        property string text: I18n.text("Delegate", "Delegar")
                        property bool isHovered: delegateMouse.containsMouse
                        property bool isPressed: delegateMouse.pressed
                        signal clicked()
                        enabled: panel.delegationState !== "running"
                        implicitWidth: delegateLabel.implicitWidth + Style.spacing.controlPaddingX * 2
                        implicitHeight: Style.spacing.controlHeight
                        radius: Style.cornerRadius
                        color: Style.controlFill(activeFocus, isHovered || isPressed, Color.popups.text, Color.accent)
                        borderSpec: Border.controlSpec(activeFocus ? "focus" : (isHovered || isPressed ? "hover-cursor" : "normal"), Color.popups.text, Color.accent)
                        Text {
                            id: delegateLabel
                            anchors.centerIn: parent
                            text: delegateButton.text
                            visible: !delegateButton.isSending
                            color: Color.popups.text
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                        }
                        BusyIndicator {
                            anchors.centerIn: parent
                            width: Style.font.body
                            height: Style.font.body
                            visible: delegateButton.isSending
                            running: visible
                            Accessible.name: I18n.text("Sending", "Enviando")
                        }
                        MouseArea {
                            id: delegateMouse
                            anchors.fill: parent
                            enabled: delegateButton.enabled
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: delegateButton.clicked()
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: I18n.text("Delegate task to %1", "Delegar tarefa para %1").arg(model.displayName)
                        Layout.alignment: Qt.AlignRight
                        onClicked: {
                            panel.selectedProfile = model.profileName
                            panel.delegate()
                        }
                    }
                    BorderSurface {
                        id: clearResponseButton
                        property bool isHovered: clearResponseMouse.containsMouse
                        property bool isPressed: clearResponseMouse.pressed
                        property string text: I18n.text("Clear", "Limpar")
                        visible: panel.responseFor(model.profileName).length > 0
                                  || (panel.pendingProfile === model.profileName && panel.delegationMessage.length > 0)
                        enabled: panel.delegationState !== "running"
                        implicitWidth: clearResponseLabel.implicitWidth + Style.spacing.controlPaddingX * 2
                        implicitHeight: Style.spacing.controlHeight
                        radius: Style.cornerRadius
                        color: Style.controlFill(activeFocus, isHovered || isPressed, Color.popups.text, Color.accent)
                        borderSpec: Border.controlSpec(activeFocus ? "focus" : (isHovered || isPressed ? "hover-cursor" : "normal"), Color.popups.text, Color.accent)
                        Text {
                            id: clearResponseLabel
                            anchors.centerIn: parent
                            text: clearResponseButton.text
                            color: Color.popups.text
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                        }
                        MouseArea {
                            id: clearResponseMouse
                            anchors.fill: parent
                            enabled: clearResponseButton.enabled
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: clearResponseButton.clicked()
                        }
                        signal clicked()
                        Accessible.role: Accessible.Button
                        Accessible.name: I18n.text("Clear bot response for %1", "Limpar retorno do bot %1").arg(model.displayName)
                        Layout.alignment: Qt.AlignRight
                        onClicked: panel.clearResponse(model.profileName)
                    }
                    }
                    Label {
                        text: panel.delegationMessage
                        visible: panel.pendingProfile === model.profileName && text.length > 0
                        textFormat: Text.PlainText
                        font.family: OmarchyTokens.fontFamily
                        font.pixelSize: OmarchyTokens.fontBodySmall
                        color: OmarchyTokens.mutedText
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

    property string pendingPayload: ""
    property string pendingTask: ""
    property string pollPath: ""

    function delegate() {
        if (delegateRequest.running || delegationState === "running")
            return
        var profile = delegationProfile()
        var task = draftFor(profile).trim()
        if (!gatewayUrl || !profile || !task) {
            delegationState = "failed"
            delegationMessage = I18n.text("Not sent: select a profile, configure the gateway and enter a task.", "Não enviado: selecione um perfil, configure o gateway e digite uma tarefa.")
            return
        }
        pendingTask = task
        pendingProfile = profile
        pendingPayload = JSON.stringify({url: gatewayUrl, profile: profile, text: pendingTask,
            transport: "canonical-chat", async: true}) + "\n"
        delegationState = "running"
        delegationMessage = I18n.text("Creating session and sending task…", "Criando sessão e enviando tarefa…")
        delegateExited = false
        delegateOutputFinished = false
        delegateStarted = false
        delegateOutput = ""
        delegateExitCode = -1
        delegateExitStatus = -1
        delegationWatchdog.interval = delegationTimeoutMs
        delegationWatchdog.restart()
        delegateRequest.stdinEnabled = true
        delegateRequest.command = [pythonExecutable, delegateFile]
        delegateRequest.running = true
    }

    readonly property string delegateFile: decodeURIComponent(Qt.resolvedUrl("../scripts/hermes_delegate.py").toString().replace(/^file:\/\//, ""))

    property bool delegateExited: false
    property bool delegateOutputFinished: false
    property bool delegateStarted: false
    property int delegationTimeoutMs: 120000
    property string delegateOutput: ""
    property int delegateExitCode: -1
    property int delegateExitStatus: -1

    function finishDelegation() {
        if (!delegateExited || !delegateOutputFinished || delegationState !== "running")
            return
        delegationWatchdog.stop()
        var response = null
        try { response = JSON.parse(delegateOutput) } catch (error) {}
        if (response && response.ok === true && response.state === "submitted" && response.poll_path) {
            pollPath = String(response.poll_path)
            delegationMessage = I18n.text("Task sent by the plugin; waiting for bot response…", "Tarefa enviada pelo plugin; aguardando retorno do bot…")
            delegationState = "running"
            delegationWatchdog.restart()
            pollTimer.restart()
            delegateOutput = ""
            return
        }
        if (delegateExitCode === 0 && delegateExitStatus === 0 && response
                && response.ok === true && (response.state === "completed" || response.state === "submitted")) {
            delegationState = response.state
            var completion = response.completion ? String(response.completion) : ""
            delegationMessage = response.state === "completed"
                ? (completion.length > 0
                    ? I18n.text("Bot concluído: %1", "Bot concluído: %1").arg(completion)
                    : I18n.text("Bot concluiu a tarefa.", "Bot concluiu a tarefa."))
                : I18n.text("Enviado ao bot; conclusão ainda não confirmada.", "Enviado ao bot; conclusão ainda não confirmada.")
            setResponse(pendingProfile, completion.length > 0 ? completion : delegationMessage)
            if (draftFor(pendingProfile) === pendingTask)
                setDraft(pendingProfile, "")
        } else if (delegateExitCode === 0 && delegateExitStatus === 0 && response
                   && response.ok === false && (response.state === "failed" || response.state === "delivery-uncertain")) {
            delegationState = response.state
            delegationMessage = response.state === "failed"
                ? I18n.text("Bot informou falha ao executar a tarefa.", "Bot informou falha ao executar a tarefa.")
                : I18n.text("Entrega não confirmada; confira o Bot Chat antes de reenviar.", "Entrega não confirmada; confira o Bot Chat antes de reenviar.")
            setResponse(pendingProfile, delegationMessage)
        } else {
            delegationState = "delivery-uncertain"
            delegationMessage = I18n.text("Delivery not confirmed. Check Hermes before resending to avoid duplicates.", "Entrega não confirmada. Confira no Hermes antes de reenviar para evitar duplicatas.")
            setResponse(pendingProfile, delegationMessage)
        }
        pendingTask = ""
        pendingPayload = ""
        delegateOutput = ""
    }

    Timer {
        id: delegationWatchdog
        // A stalled helper must never leave the panel spinning forever.
        interval: panel.delegationTimeoutMs
        repeat: false
        onTriggered: {
            if (panel.delegationState !== "running")
                return
            if (panel.delegateStarted) {
                panel.delegationState = "delivery-uncertain"
                panel.delegationMessage = I18n.text("Delivery not confirmed. Check Hermes before resending to avoid duplicates.", "Entrega não confirmada. Confira no Hermes antes de reenviar para evitar duplicatas.")
            } else {
                panel.delegationState = "failed"
                panel.delegationMessage = I18n.text("Task not sent: the delegation helper could not start.", "Tarefa não enviada: o auxiliar de delegação não pôde iniciar.")
            }
            pendingTask = ""
            pendingPayload = ""
            delegateOutput = ""
            delegateRequest.running = false
        }
    }

    Timer {
        id: pollTimer
        interval: 700
        repeat: true
        onTriggered: {
            if (pollPath.length === 0 || pollRequest.running)
                return
            pollRequest.command = [pythonExecutable, delegateFile, "--poll", pollPath]
            pollRequest.running = true
        }
    }

    Process {
        id: pollRequest
        command: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var result = {}
                try { result = JSON.parse(text) } catch (error) { return }
                if (result.state === "pending")
                    return
                pollTimer.stop()
                panel.pollPath = ""
                panel.delegateOutput = JSON.stringify(result)
                panel.delegateExitCode = 0
                panel.delegateExitStatus = 0
                panel.delegateExited = true
                panel.delegateOutputFinished = true
                panel.finishDelegation()
            }
        }
    }

    Process {
        id: delegateRequest
        stdinEnabled: true
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                panel.delegateOutput = text
                panel.delegateOutputFinished = true
                panel.finishDelegation()
            }
        }
        onStarted: {
            panel.delegateStarted = true
            delegateRequest.write(panel.pendingPayload)
            // QProcess drains queued bytes before closing the write channel.
            delegateRequest.stdinEnabled = false
            panel.pendingPayload = ""
        }
        onRunningChanged: {
            // A failed start clears the process without raising "exited".
            if (!delegateRequest.running && panel.delegationState === "running"
                    && !panel.delegateStarted && !panel.delegateExited) {
                delegationWatchdog.stop()
                panel.delegateExited = true
                panel.delegateOutputFinished = true
                panel.delegationState = "failed"
                panel.delegationMessage = I18n.text("Task not sent: the delegation helper could not start.", "Tarefa não enviada: o auxiliar de delegação não pôde iniciar.")
                panel.pendingTask = ""
                panel.pendingPayload = ""
            }
        }
        onExited: function(exitCode, exitStatus) {
            delegationWatchdog.stop()
            panel.delegateExitCode = exitCode
            panel.delegateExitStatus = exitStatus
            panel.delegateExited = true
            panel.finishDelegation()
        }
    }
}
