pragma Singleton
import QtQuick

QtObject {
    readonly property bool portuguese: String(Qt.locale().name).toLowerCase().indexOf("pt") === 0

    function text(en, pt) {
        return portuguese ? pt : en
    }
}
