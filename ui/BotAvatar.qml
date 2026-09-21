import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: avatar
    property string displayName: "Bot"
    property string imageSource: ""
    property bool imageValid: false
    property int diameter: 48
    width: diameter
    height: diameter

    Accessible.role: Accessible.Graphic
    Accessible.name: imageValid ? qsTr("Avatar de %1").arg(displayName)
                                  : qsTr("Avatar não disponível para %1").arg(displayName)
    Accessible.description: qsTr("Identificação visual; o nome do bot também é exibido ao lado")

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: OmarchyTokens.accent
        border.color: OmarchyTokens.popupBorder
        border.width: 1

        Image {
            anchors.fill: parent
            anchors.margins: 1
            visible: avatar.imageValid && avatar.imageSource.length > 0
            source: avatar.imageSource
            fillMode: Image.PreserveAspectCrop
            asynchronous: false
            smooth: true
        }

        Text {
            anchors.centerIn: parent
            visible: !avatar.imageValid || avatar.imageSource.length === 0
            text: avatar.displayName.trim().length > 0
                  ? avatar.displayName.trim().slice(0, 2).toUpperCase()
                  : "?"
            color: OmarchyTokens.popupBackground
            font.bold: true
            font.pixelSize: Math.max(12, avatar.diameter * 0.32)
            Accessible.ignored: true
        }
    }
}
