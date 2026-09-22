import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property var shell: null
    property var manifest: null
    property var pluginRegistry: null
    property var settings: null
    property string pluginDir: ""
    property string gatewayUrl: ""
    property var profiles: []
    property bool loading: false
    property string error: ""
    property string selectedProfile: ""
    property var avatarSources: ({})
    readonly property string viewState: loading ? "loading" : error.length > 0 ? "error" : profiles.length === 0 ? "empty" : "ready"
    readonly property bool configurationRequired: false
    readonly property string profilesMethod: "profiles.list"
    readonly property string avatarMethod: "profiles.get_asset"
    readonly property bool includeSessions: false
    // profiles.list params: {"include_sessions": false}
    readonly property bool delegationBlocked: false
    readonly property string delegationState: "ready"
    readonly property string delegationMethod: "prompt.submit"

    function helperPath() {
        return root.pluginDir + "/scripts/hermes_profiles.py"
    }

    function refreshProfiles() {
        if (root.loading)
            return
        root.loading = true
        root.error = ""
        request.command = ["python3", helperPath()]
        if (root.gatewayUrl.length > 0)
            request.command.push("--url", root.gatewayUrl)
        request.running = true
    }

    function fetchAvatar(profileName) {
        if (root.configurationRequired || !profileName)
            return
        avatarRequest.command = ["python3", helperPath(), "--url", root.gatewayUrl,
                                 "--profile", String(profileName), "--asset", "avatar"]
        avatarRequest.running = true
    }

    function acceptResponse(text) {
        try {
            var response = JSON.parse(text)
            if (!response.ok) {
                root.error = response.error === "configuration_required"
                        ? qsTr("Configure a URL loopback do gateway Hermes.")
                        : qsTr("Não foi possível consultar o gateway Hermes.")
                return
            }
            if (response.kind === "avatar" && response.asset && response.asset.found === true) {
                var avatars = Object.assign({}, root.avatarSources)
                avatars[response.profile] = response.asset.data || ""
                root.avatarSources = avatars
                return
            }
            if (response.kind === "profiles" && Array.isArray(response.profiles)) {
                if (response.gateway_url)
                    root.gatewayUrl = String(response.gateway_url)
                root.profiles = response.profiles
                if (root.profiles.length === 0)
                    root.selectedProfile = ""
                else if (!root.profileExists(root.selectedProfile))
                    root.selectedProfile = root.profileName(root.profiles[0])
                return
            }
            root.error = qsTr("Resposta do gateway Hermes inválida.")
        } catch (e) {
            root.error = qsTr("Resposta do gateway Hermes inválida.")
        }
    }

    function profileName(profile) {
        if (!profile)
            return ""
        return String(profile.name !== undefined ? profile.name
                     : profile.id !== undefined ? profile.id : "")
    }

    function profileExists(name) {
        for (var i = 0; i < root.profiles.length; i++) {
            if (root.profileName(root.profiles[i]) === name)
                return true
        }
        return false
    }

    Component.onCompleted: {
        if (!root.pluginDir && root.manifest && root.manifest.pluginDir)
            root.pluginDir = root.manifest.pluginDir
        if (!root.gatewayUrl && root.settings && root.settings.gatewayUrl)
            root.gatewayUrl = String(root.settings.gatewayUrl)
        Qt.callLater(root.refreshProfiles)
    }

    Process {
        id: request
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.acceptResponse(text)
        }
        onExited: {
            root.loading = false
            if (exitCode !== 0 && root.error.length === 0)
                root.error = qsTr("Helper do gateway Hermes falhou.")
        }
    }

    Process {
        id: avatarRequest
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                // Avatar delivery is deliberately on-demand; the panel may bind
                // this result in a later slice without changing roster state.
            }
        }
    }
}
