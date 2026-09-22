import QtQuick
import Quickshell

ShellRoot {
    id: harness
    property var panel
    property int phase: 0
    property int ticks: 0
    property int failures: 0
    function check(ok, label) {
        console.log("DELEGATION_ASSERT " + (ok ? "PASS " : "FAIL ") + label)
        if (!ok) failures++
    }
    Component.onCompleted: {
        var component = Qt.createComponent("plugin/ui/BotPanel.qml")
        if (component.status !== Component.Ready) {
            console.log("DELEGATION_FATAL " + component.errorString()); Qt.quit(); return
        }
        panel = component.createObject(null, {profiles: [{name: "fixture"}],
            gatewayUrl: "ws://127.0.0.1:1/api/ws", pythonExecutable: "/usr/bin/python3"})
        if (!panel) { console.log("DELEGATION_FATAL create"); Qt.quit(); return }
        if (Quickshell.env("PBH_TIMEOUT")) panel.delegationTimeoutMs = 250
        if (Quickshell.env("PBH_MISSING")) panel.pythonExecutable = "/nonexistent-pbh-fixture-python"
        panel.taskText = ""
        panel.delegate()
        check(panel.delegationState === "failed", "empty input rejected synchronously")
        panel.taskText = "fixture original — not a user task"
        panel.delegate()
        panel.taskText = "fixture newer draft"
        // A repeated action must not mutate the captured request.
        panel.delegate()
    }
    Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            if (!harness.panel) return
            harness.ticks++
            if (harness.panel.delegationState === "running" && harness.ticks < 80) return
            var expected = Quickshell.env("PBH_EXPECTED")
            harness.check(harness.panel.delegationState === expected, "state " + expected + " got " + harness.panel.delegationState)
            harness.check(harness.panel.taskText === "fixture newer draft", "new draft preserved")
            harness.check(harness.panel.delegationMessage.length > 0, "visible status message")
            console.log("DELEGATION_RESULT " + harness.failures)
            harness.panel.destroy()
            Qt.quit()
        }
    }
}
