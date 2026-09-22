import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

ItemDelegate {
    id: row
    property string botId: ""
    property string botName: "Bot"
    property string botRole: ""
    property bool avatarValid: false
    property string avatarSource: ""
    property string availability: "unknown"
    property string avatarShape: "squircle"
    property color avatarFill: OmarchyTokens.accent
    property bool selected: false

    implicitHeight: 72
    highlighted: selected
    Accessible.role: Accessible.ListItem
    Accessible.name: qsTr("%1, %2").arg(botName).arg(botRole.length > 0 ? botRole : I18n.text("role not provided", "função não informada"))
    Accessible.description: selected ? qsTr("Selecionado") : qsTr("Pressione Enter ou Espaço para selecionar")
    Accessible.onPressAction: clicked()

    background: Rectangle {
        radius: OmarchyTokens.cornerRadius
        color: row.selected ? Qt.alpha(OmarchyTokens.accent, 0.18) : "transparent"
        border.color: row.activeFocus ? OmarchyTokens.focus : (row.selected ? OmarchyTokens.accent : OmarchyTokens.popupBorder)
        border.width: row.activeFocus || row.selected ? 2 : 1
    }

    contentItem: RowLayout {
        spacing: OmarchyTokens.spacing
        Avatar {
            diameter: 44
            shape: row.avatarShape
            fill: row.avatarFill
            image: row.avatarValid && row.avatarSource.length > 0 ? row.avatarSource : ""
            animate: false
            Layout.alignment: Qt.AlignVCenter
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Label {
                text: row.botName
                textFormat: Text.PlainText
                color: OmarchyTokens.text
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Label {
                text: row.botRole.length > 0 ? row.botRole : I18n.text("Role not provided", "Função não informada")
                textFormat: Text.PlainText
                color: OmarchyTokens.mutedText
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Label {
                text: I18n.text("Availability: %1", "Disponibilidade: %1").arg(row.availability)
                textFormat: Text.PlainText
                color: OmarchyTokens.mutedText
                font.pixelSize: 11
                Layout.fillWidth: true
            }
        }
    }
}
