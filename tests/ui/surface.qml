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
    property var field
    property var btn
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
                    autoRefreshRoster: false,
                    rosterProfiles: [
                        {name: "synthetic-a", display_name: "SYNTHETIC A — not a real bot", description: "UI regression fixture"},
                        {name: "synthetic-b", display_name: "SYNTHETIC B — not a real bot", description: "UI regression fixture"},
                        {name: "synthetic-c", display_name: "SYNTHETIC C — not a real bot", description: "UI regression fixture"},
                        {name: "synthetic-d", display_name: "SYNTHETIC D — not a real bot", description: "UI regression fixture"},
                        {name: "synthetic-e", display_name: "SYNTHETIC E — not a real bot", description: "UI regression fixture"},
                        {name: "synthetic-f", display_name: "SYNTHETIC F — not a real bot", description: "UI regression fixture"}
                    ]});
                var all = harness.objects(harness.widget);
                harness.trigger = all.find(o => typeof o.triggerPress === "function");
                harness.panel = all.find(o => typeof o.rebuildProfiles === "function");
                harness.list = all.find(o => o.rosterContainer === true);
                harness.surface = all.find(o => o.anchorItem !== undefined && o.open !== undefined)
                    || all.find(o => o.popupType !== undefined);
                if (!harness.trigger || !harness.panel || !harness.list || !harness.surface) {
                    console.log("PBH_FATAL cannot locate production objects"); Qt.quit(); return;
                }
                harness.check(!harness.widget.panelOpen, "initially closed");
                harness.trigger.triggerPress(Qt.LeftButton);
            } else if (harness.phase === 1) {
                var pAll = harness.objects(harness.panel);
                harness.check(harness.widget.panelOpen && harness.surface.visible, "host trigger opens panel");
                var window = harness.panel.QsWindow.window;
                harness.check(window && window !== barWindow && window.height > 26,
                              "independent panel window taller than 26px bar");
                harness.check(harness.list.interactive === false, "roster does not scroll");
                harness.check(harness.list.height >= harness.list.contentHeight,
                    "roster height expands to all items");
                var rows = [harness.list.itemAtIndex(0), harness.list.itemAtIndex(1), harness.list.itemAtIndex(5)];
                var rowControls = rows.map(r => r && r.botName !== undefined ? r : (r && r.children ? r.children.find(c => c.botName !== undefined) : null));
                console.log("PBH_GEOMETRY " + JSON.stringify({barHeight: barWindow.height, panelHeight: window ? window.height : null,
                    listHeight: harness.list.height, rows: rowControls.map(r => r ? {name: r.botName, y: r.y, height: r.height} : null)}));
                harness.check(rowControls.every(r => r && r.botName.indexOf("SYNTHETIC") === 0 && r.height >= r.implicitHeight
                    && r.y >= harness.list.contentY && r.y + r.height <= harness.list.contentY + harness.list.height),
                    "two explicitly synthetic rows fully inside viewport");
                harness.check(harness.panel.delegationState === "idle", "delegation starts idle");
                rowControls[2].clicked();
                harness.check(harness.panel.selectedEditorHeight > 0,
                    "selected editor reserves input and response space");
                Qt.callLater(function() {
                    harness.check(harness.list.height > harness.panel.rosterHeight,
                        "list reserves space below the last bot for the editor");
                    harness.check(harness.list.height >= harness.list.contentHeight || harness.list.contentHeight === harness.list.implicitHeight,
                        "list expands for the selected editor");
                    harness.check(harness.panel.implicitHeight >= harness.list.height,
                        "panel height includes the selected editor");
                    harness.check(harness.panel.implicitHeight >= harness.panel.layoutHeight,
                        "panel height contains roster and editor");
                });
                var responseDisplay = pAll.find(o => o.visible && o.placeholderText !== undefined
                    && (String(o.placeholderText).indexOf("Bot response will appear here") >= 0
                        || String(o.placeholderText).indexOf("O retorno do bot aparecerá aqui") >= 0));
                harness.check(!responseDisplay, "bot response is not displayed in the inline editor");
                var clearResponseControl = pAll.find(o => o.visible && o.text !== undefined
                    && (String(o.text) === "Clear" || String(o.text) === "Limpar"));
                harness.check(!clearResponseControl, "response clear button is not displayed");
                harness.field = pAll.find(o => o.visible && o.placeholderText !== undefined
                    && (String(o.placeholderText).indexOf("Descreva a tarefa") >= 0
                        || String(o.placeholderText).indexOf("Describe the task") >= 0));
                harness.btn = pAll.find(o => typeof o.clicked === "function" && o.text !== undefined
                    && (String(o.text).indexOf("➤") === 0 || String(o.text).indexOf("Delegar") === 0 || String(o.text).indexOf("Delegate") === 0
                        || String(o.text).indexOf("Enviando") === 0 || String(o.text).indexOf("Sending") === 0));
                if (!harness.field || !harness.btn) {
                    console.log("PBH_FATAL cannot locate task field/button"); Qt.quit(); return;
                }
                harness.trigger.triggerPress(Qt.LeftButton);
            } else if (harness.phase === 2) {
                harness.check(!harness.widget.panelOpen && !harness.surface.visible, "trigger closes panel after fade");
                harness.trigger.triggerPress(Qt.LeftButton);
            } else if (harness.phase === 3) {
                harness.surface.close();
            } else if (harness.phase === 4) {
                harness.trigger.triggerPress(Qt.LeftButton);
            } else if (harness.phase === 5) {
                harness.check(harness.field.enabled && harness.btn.enabled,
                    "task field and Delegate button resolved and enabled");
                harness.field.text = "tarefa de teste";
                harness.check(harness.field.text === "tarefa de teste" && harness.panel.taskText === "tarefa de teste",
                    "typing into task field syncs panel.taskText");
                harness.check(String(harness.btn.text).indexOf("➤") === 0,
                    "Delegate button uses send symbol");
                harness.btn.clicked();
                console.log("PBH_DELEGATE " + JSON.stringify({btnText: harness.btn.text,
                    state: harness.panel.delegationState, msg: harness.panel.delegationMessage}));
                harness.check(harness.panel.delegationState !== "idle",
                    "clicking Delegate moves delegationState off idle");
            } else if (harness.phase === 6) {
                console.log("PBH_DELEGATE " + JSON.stringify({btnText: harness.btn.text,
                    state: harness.panel.delegationState, msg: harness.panel.delegationMessage,
                    running: harness.panel.delegateRequest ? harness.panel.delegateRequest.running : null}));
                harness.check(harness.panel.delegationState === "failed"
                    && harness.panel.delegationMessage.length > 0,
                    "empty-gateway environment resolves to failed with visible message");
            } else if (harness.phase === 7) {
                var syntheticCompletion = "SYNTHETIC FULL BOT RESPONSE — must remain internal";
                harness.panel.pendingProfile = "synthetic-f";
                harness.panel.pendingTask = "synthetic task";
                harness.panel.delegationState = "running";
                harness.panel.delegateExited = true;
                harness.panel.delegateOutputFinished = true;
                harness.panel.delegateExitCode = 0;
                harness.panel.delegateExitStatus = 0;
                harness.panel.delegateOutput = JSON.stringify({ok: true, state: "completed", completion: syntheticCompletion});
                harness.panel.finishDelegation();
                harness.check(harness.panel.delegationMessage.indexOf(syntheticCompletion) < 0,
                    "full bot response is not rendered as delegation status");
                harness.check(harness.panel.responseFor("synthetic-f") === syntheticCompletion,
                    "full bot response remains available in internal per-profile state");
            } else {
                console.log("PBH_RESULT " + harness.failures);
                Qt.quit();
            }
            harness.phase++;
        }
    }
}
