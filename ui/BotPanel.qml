import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: panel

    // Persistent read-only gateway service supplied by BarWidget.
    property var service: null
    property var adapter: null
    property var profiles: []
    property string viewState: "error"
    property string errorMessage: I18n.text("Adapter not connected.", "Adaptador não conectado.")
    property string selectedProfile: ""
    property bool delegationEnabled: false
    property string delegateTask: "unsupported"

    implicitWidth: 360
    implicitHeight: Math.min(560, content.implicitHeight + OmarchyTokens.spacing * 2)

    function profileValue(profile, snake, camel, fallback) {
        if (!profile)
            return fallback
        if (profile[snake] !== undefined && profile[snake] !== null)
            return String(profile[snake])
        if (profile[camel] !== undefined && profile[camel] !== null)
            return String(profile[camel])
        return fallback
    }

    function profileMeta(profile) {
        var meta = profile && profile.ui_meta && profile.ui_meta["hermes-bots"]
        return meta && typeof meta === "object" ? meta : {}
    }

    function rebuildProfiles() {
        profileModel.clear()
        for (var i = 0; i < profiles.length; i++) {
            var profile = profiles[i]
            var name = profileValue(profile, "name", "id", "profile-" + i)
            var displayName = profileValue(profile, "display_name", "displayName", name)
            var meta = profileMeta(profile)
            profileModel.append({
                profileName: name,
                displayName: displayName,
                description: profileValue(profile, "description", "description", I18n.text("Description not provided", "Descrição não informada")),
                hasAvatar: Boolean(profile && (profile.has_avatar || profile.hasAvatar)),
                avatarSource: profileValue(profile, "avatar", "avatarSource", ""),
                avatarShape: meta.shape || "squircle",
                avatarColor: meta.color || "#777777"
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
            Accessible.name: qsTr("Carregando perfis")
        }
        Label {
            visible: panel.viewState === "empty"
            text: qsTr("O adaptador retornou uma lista vazia.")
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
            Layout.preferredHeight: Math.min(contentHeight, 240)
            Layout.fillHeight: true
            Accessible.role: Accessible.List
            Accessible.name: qsTr("Perfis Hermes")
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
                availability: "unknown"
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
            title: qsTr("Delegar tarefa")
            Layout.fillWidth: true
            enabled: false
            Accessible.name: qsTr("Delegação desabilitada")
            ColumnLayout {
                anchors.fill: parent
                TextArea {
                    placeholderText: qsTr("Disponível quando o adapter RPC for verificado")
                    readOnly: true
                    enabled: false
                    Layout.fillWidth: true
                    Layout.preferredHeight: 58
                    Accessible.name: qsTr("Texto da delegação desabilitado")
                }
                Button {
                    text: qsTr("Delegar (indisponível)")
                    enabled: false
                    Accessible.name: qsTr("Delegar tarefa — RPC_RUNTIME_UNVERIFIED")
                    Accessible.description: qsTr("Nenhum prompt é enviado pelo painel.")
                    Layout.alignment: Qt.AlignRight
                }
                Label {
                    text: qsTr("RPC_RUNTIME_UNVERIFIED — seleção visual apenas; transporte não conectado.")
                    textFormat: Text.PlainText
                    color: OmarchyTokens.mutedText
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }
    }
}
