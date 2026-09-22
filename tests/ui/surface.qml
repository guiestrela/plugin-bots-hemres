import QtQuick
import Quickshell

// Isolated synthetic fixture: no shell/service, endpoint or transport injection.
ShellRoot {
    id: harness
    property var widget
    property var trigger
    property var panel
    property var list
    property var surface
    property int phase: 0
    property int failures: 0
    QtObject {
        id: barStub
        property bool vertical: false
        property int barSize: 26
        property string position: "top"
        property string fontFamily: "sans-serif"
        property color barForeground: "white"
        property color urgent: "red"
        property bool foregroundAnimationEnabled: false
        property var activePopout: null
        function hideTooltip(item) {}
        function showTooltip(item, text) {}
        function requestPopout(owner) { activePopout = owner }
        function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    }
    FloatingWindow {
        id: barWindow
        visible: true
        implicitWidth: 800
        implicitHeight: 26
    }
    function objects(start) {
        var seen = [], queue = [start];
        while (queue.length) {
            var o = queue.shift();
            if (!o || seen.indexOf(o) !== -1) continue;
            seen.push(o);
            for (var key of ["children", "resources", "data"]) {
                var values = o[key];
                if (values && typeof values.length === "number")
                    for (var i = 0; i < values.length; i++) queue.push(values[i]);
            }
            if (o.contentItem) queue.push(o.contentItem);
        }
        return seen;
    }
    function check(ok, message) {
        console.log("PBH_ASSERT " + (ok ? "PASS " : "FAIL ") + message);
        if (!ok) failures++;
    }
    Timer {
        interval: 400
        running: true
        repeat: true
        onTriggered: {
            if (harness.phase === 0) {
                var component = Qt.createComponent("plugin/BarWidget.qml");
                if (component.status !== Component.Ready) {
                    console.log("PBH_FATAL " + component.errorString()); Qt.quit(); return;
                }
                harness.widget = component.createObject(barWindow.contentItem, {bar: barStub, width: 29, height: 26,
                    rosterProfiles: [
                        {name: "synthetic-a", display_name: "SYNTHETIC A — not a real bot", description: "UI regression fixture"},
                        {name: "synthetic-b", display_name: "SYNTHETIC B — not a real bot", description: "UI regression fixture"}
                    ]});
                var all = harness.objects(harness.widget);
                harness.trigger = all.find(o => typeof o.triggerPress === "function");
                harness.panel = all.find(o => typeof o.rebuildProfiles === "function");
                harness.list = all.find(o => o.keyNavigationEnabled !== undefined);
                harness.surface = all.find(o => o.anchorItem !== undefined && o.open !== undefined)
                    || all.find(o => o.popupType !== undefined);
                if (!harness.trigger || !harness.panel || !harness.list || !harness.surface) {
                    console.log("PBH_FATAL cannot locate production objects"); Qt.quit(); return;
                }
                harness.check(!harness.widget.panelOpen, "initially closed");
                harness.trigger.triggerPress(Qt.LeftButton);
            } else if (harness.phase === 1) {
                harness.check(harness.widget.panelOpen && harness.surface.visible, "host trigger opens panel");
                var window = harness.panel.QsWindow.window;
                harness.check(window && window !== barWindow && window.height > 26,
                              "independent panel window taller than 26px bar");
                var rows = [harness.list.itemAtIndex(0), harness.list.itemAtIndex(1)];
                console.log("PBH_GEOMETRY " + JSON.stringify({barHeight: barWindow.height, panelHeight: window ? window.height : null,
                    listHeight: harness.list.height, rows: rows.map(r => r ? {name: r.botName, y: r.y, height: r.height} : null)}));
                harness.check(rows.every(r => r && r.botName.indexOf("SYNTHETIC") === 0 && r.height >= r.implicitHeight
                    && r.y >= harness.list.contentY && r.y + r.height <= harness.list.contentY + harness.list.height),
                    "two explicitly synthetic rows fully inside viewport");
                harness.check(harness.panel.delegationEnabled === false, "delegation remains disabled");
                harness.trigger.triggerPress(Qt.LeftButton);
            } else if (harness.phase === 2) {
                harness.check(!harness.widget.panelOpen && !harness.surface.visible, "trigger closes panel after fade");
                harness.trigger.triggerPress(Qt.LeftButton);
            } else if (harness.phase === 3) {
                harness.surface.close();
            } else {
                harness.check(!harness.widget.panelOpen && !harness.surface.visible, "native close synchronizes owner");
                console.log("PBH_RESULT " + harness.failures);
                Qt.quit();
            }
            harness.phase++;
        }
    }
}
