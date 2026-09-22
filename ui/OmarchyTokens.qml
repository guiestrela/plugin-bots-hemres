pragma Singleton
import QtQuick 2.15
import qs.Commons

QtObject {
    // Adapter semântico para os tokens vivos do Omarchy. Não fixa uma paleta:
    // Color/Style são atualizados pelo shell quando o tema muda.
    readonly property string source: "qs.Commons Color + Style"

    readonly property color popupBackground: Color.popups.background
    readonly property color popupSurface: Color.popups.background
    readonly property color popupBorder: Color.popups.border
    readonly property color text: Color.popups.text
    readonly property color mutedText: Color.muted
    readonly property color accent: Color.accent
    readonly property color urgent: Color.urgent
    readonly property color success: Color.accent
    readonly property color focus: Style.focusStateColor(Color.popups.text, Color.accent, Color.urgent)

    readonly property int spacing: Style.spacing.lg
    readonly property int compactSpacing: Style.spacing.sm
    readonly property int cornerRadius: Style.cornerRadius
    readonly property int controlHeight: Style.spacing.controlHeight
    readonly property string fontFamily: Style.font.family
    readonly property int fontCaption: Style.font.caption
    readonly property int fontBodySmall: Style.font.bodySmall
    readonly property int fontBody: Style.font.body
    readonly property int fontSubtitle: Style.font.subtitle
}
