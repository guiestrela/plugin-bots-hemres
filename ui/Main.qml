import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

ApplicationWindow {
    id: window
    visible: true
    width: 560
    height: 820
    minimumWidth: 420
    minimumHeight: 640
    title: qsTr("Bots Hermes — harness QML isolado")
    color: OmarchyTokens.popupBackground

    property string viewState: "ready"
    property string selectedBotId: "backend"
    property bool sending: false
    property string draft: ""

    ListModel {
        id: bots
        ListElement { botId: "backend"; botName: "Backend"; botRole: "Implementação e APIs"; avatarValid: false; avatarSource: ""; availability: "unknown" }
        ListElement { botId: "research"; botName: "Research"; botRole: "Pesquisa"; avatarValid: false; avatarSource: ""; availability: "unknown" }
        ListElement { botId: "long-name"; botName: "Bot com um nome deliberadamente longo para testar leitura"; botRole: "Função não verificada"; avatarValid: false; avatarSource: ""; availability: "unavailable" }
    }

    function stateTitle() {
        switch (viewState) {
        case "loading": return qsTr("Carregando bots…")
        case "empty": return qsTr("Nenhum bot disponível")
        case "error": return qsTr("Adaptador indisponível")
        case "unsupported": return qsTr("Capacidade não verificada")
        case "streaming": return qsTr("Streaming não verificado")
        case "approval": return qsTr("Aprovação redigida")
        case "secret-sudo": return qsTr("Secret e sudo recusados")
        default: return qsTr("Bots disponíveis")
        }
    }

    function stateDescription() {
        switch (viewState) {
        case "loading": return qsTr("O roster está sendo consultado. Nenhum envio está disponível.")
        case "empty": return qsTr("Lista vazia confirmada pelo fixture; não há perfis para configurar.")
        case "error": return qsTr("Não foi possível consultar o adaptador. Tente novamente; isto não é uma lista vazia.")
        case "unsupported": return qsTr("RPC_RUNTIME_UNVERIFIED: capacidades não verificadas permanecem indisponíveis.")
        case "streaming": return qsTr("Streaming permanece unsupported até a ponte e o fechamento do turno serem verificados.")
        case "approval": return qsTr("Somente resumo redigido e escolhas allowlisted são exibidos.")
        case "secret-sudo": return qsTr("Credenciais nunca são capturadas, armazenadas, ecoadas ou enviadas pelo painel.")
        default: return qsTr("Fixture local; nenhum adaptador Hermes está conectado.")
        }
    }

    header: ToolBar {
        Accessible.role: Accessible.ToolBar
        Accessible.name: qsTr("Controles do harness")
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: OmarchyTokens.spacing
            anchors.rightMargin: OmarchyTokens.spacing
            Label {
                text: qsTr("Bots Hermes")
                textFormat: Text.PlainText
                color: OmarchyTokens.text
                font.bold: true
                Layout.fillWidth: true
            }
            ComboBox {
                id: statePicker
                Accessible.name: qsTr("Estado de fixture")
                model: [qsTr("Pronto"), qsTr("Carregando"), qsTr("Vazio"), qsTr("Erro"), qsTr("Unsupported"), qsTr("Streaming"), qsTr("Aprovação redigida"), qsTr("Secret/sudo")]
                onActivated: window.viewState = ["ready", "loading", "empty", "error", "unsupported", "streaming", "approval", "secret-sudo"][currentIndex]
                Layout.preferredWidth: 160
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: OmarchyTokens.spacing
        spacing: OmarchyTokens.spacing

        Label {
            text: window.stateTitle()
            textFormat: Text.PlainText
            color: OmarchyTokens.text
            font.pixelSize: 22
            font.bold: true
            Layout.fillWidth: true
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Label {
            text: window.stateDescription()
            textFormat: Text.PlainText
            color: OmarchyTokens.mutedText
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        Rectangle {
            visible: window.viewState !== "ready"
            color: window.viewState === "error" || window.viewState === "secret-sudo" ? Qt.alpha(OmarchyTokens.urgent, 0.18) : Qt.alpha(OmarchyTokens.accent, 0.12)
            border.color: window.viewState === "error" || window.viewState === "secret-sudo" ? OmarchyTokens.urgent : OmarchyTokens.accent
            radius: OmarchyTokens.cornerRadius
            implicitHeight: message.implicitHeight + OmarchyTokens.spacing * 2
            Layout.fillWidth: true
            Label {
                id: message
                anchors.fill: parent
                anchors.margins: OmarchyTokens.spacing
                text: window.viewState === "approval"
                      ? qsTr("Detalhes redigidos. Escolhas: uma vez · sessão · sempre · negar")
                      : window.viewState === "secret-sudo"
                        ? qsTr("Recusado: secret.request e sudo.request não são suportados no painel.")
                        : window.stateDescription()
                textFormat: Text.PlainText
                color: OmarchyTokens.text
                wrapMode: Text.WordWrap
                Accessible.role: Accessible.Alert
                Accessible.name: text
            }
        }

        GroupBox {
            title: qsTr("Lista de bots (fixture local)")
            enabled: window.viewState === "ready" || window.viewState === "approval"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Accessible.name: qsTr("Lista de bots")
            ColumnLayout {
                anchors.fill: parent
                BusyIndicator {
                    visible: window.viewState === "loading"
                    running: visible
                    Accessible.name: qsTr("Carregando bots")
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    visible: window.viewState === "empty"
                    text: qsTr("Nenhum bot disponível")
                    textFormat: Text.PlainText
                    color: OmarchyTokens.mutedText
                    Layout.alignment: Qt.AlignHCenter
                }
                ListView {
                    id: botList
                    visible: window.viewState !== "empty" && window.viewState !== "loading"
                    model: bots
                    clip: true
                    spacing: OmarchyTokens.compactSpacing
                    focus: true
                    keyNavigationEnabled: true
                    Accessible.role: Accessible.List
                    Accessible.name: qsTr("Bots descobertos")
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    delegate: BotRow {
                        width: botList.width
                        botId: model.botId
                        botName: model.botName
                        botRole: model.botRole
                        avatarValid: model.avatarValid
                        avatarSource: model.avatarSource
                        availability: model.availability
                        selected: model.botId === window.selectedBotId
                        onClicked: window.selectedBotId = model.botId
                    }
                }
                Button {
                    text: qsTr("Atualizar roster")
                    enabled: !window.sending && window.viewState !== "loading"
                    Accessible.name: qsTr("Atualizar roster (fixture, não conecta Hermes)")
                    onClicked: window.viewState = "ready"
                    Layout.alignment: Qt.AlignRight
                }
            }
        }

        GroupBox {
            title: qsTr("Composição")
            Layout.fillWidth: true
            enabled: window.viewState === "ready" && !window.sending
            ColumnLayout {
                anchors.fill: parent
                Label {
                    text: qsTr("Destinatário: %1").arg(window.selectedBotId.length > 0 ? window.selectedBotId : qsTr("nenhum"))
                    textFormat: Text.PlainText
                    color: OmarchyTokens.text
                    Accessible.name: text
                }
                TextArea {
                    id: composer
                    placeholderText: qsTr("Tarefa (fixture; Ctrl+Enter não envia)")
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    Accessible.name: qsTr("Texto da tarefa")
                    Accessible.description: qsTr("Rascunho apenas em memória. Não inclui segredos.")
                    Layout.fillWidth: true
                    Layout.preferredHeight: 84
                }
                Label {
                    text: qsTr("Não inclua segredos. Envio real permanece unsupported.")
                    textFormat: Text.PlainText
                    color: OmarchyTokens.mutedText
                    Accessible.name: text
                }
                Button {
                    text: window.sending ? qsTr("Enviando…") : qsTr("Enviar tarefa")
                    enabled: !window.sending && window.selectedBotId.length > 0 && composer.text.trim().length > 0
                    Accessible.name: qsTr("Enviar tarefa — fixture recusará sem adaptador")
                    onClicked: {
                        window.sending = true
                        window.viewState = "unsupported"
                        window.sending = false
                    }
                    Layout.alignment: Qt.AlignRight
                }
            }
        }

        Label {
            text: qsTr("Harness isolado · sem Hermes real · sem serviço global · sem instalação/ativação")
            textFormat: Text.PlainText
            color: OmarchyTokens.mutedText
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }
    }
}
