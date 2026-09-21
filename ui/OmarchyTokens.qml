pragma Singleton
import QtQuick 2.15

QtObject {
    // Harness mirror of the semantic Omarchy tokens documented in ui-discovery.md.
    // The active plugin will bind these roles to Color.qml / Style.qml; this file
    // deliberately stays standalone and never reads ~/.config or a live shell.
    readonly property string source: "Omarchy Color.popups/Color.accent/Color.urgent + Style.spacing/Style.cornerRadius"

    readonly property color popupBackground: "#24273a"
    readonly property color popupSurface: "#303446"
    readonly property color popupBorder: "#626880"
    readonly property color text: "#c6d0f5"
    readonly property color mutedText: "#a5adce"
    readonly property color accent: "#8caaee"
    readonly property color urgent: "#e78284"
    readonly property color success: "#a6d189"
    readonly property color focus: "#f2d5cf"

    readonly property int spacing: 12
    readonly property int compactSpacing: 8
    readonly property int cornerRadius: 10
    readonly property int controlHeight: 40
}
