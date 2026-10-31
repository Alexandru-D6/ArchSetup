pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: monitor
    // Inputs are supplied by UPower in the shell and by fixtures in tests.
    property bool ready: false
    property bool present: false
    property bool onBattery: false
    property real percentage: NaN
    property var settings: ({lowBatteryPercentage: 20, criticalBatteryPercentage: 10, suspendPercentage: 3})
    property int suspendDelay: 5000
    property int alertedStage: 0
    property bool suspendIssued: false
    readonly property bool suspendPending: suspendTimer.running
    readonly property bool validSample: ready && present && Number.isFinite(percentage) && percentage >= 0 && percentage <= 100
    readonly property bool validSettings: settings && [settings.suspendPercentage, settings.criticalBatteryPercentage, settings.lowBatteryPercentage]
        .every(value => Number.isInteger(value) && value >= 1 && value <= 100)
        && settings.suspendPercentage < settings.criticalBatteryPercentage && settings.criticalBatteryPercentage < settings.lowBatteryPercentage
    signal alertRequested(string level, int percentage)
    signal cleared()
    signal suspendRequested()

    function reset() {
        suspendTimer.stop();
        alertedStage = 0;
        suspendIssued = false;
        cleared();
    }
    function evaluate() {
        if (!ready || !validSettings) { suspendTimer.stop(); return; }
        if (!present || !onBattery) { reset(); return; }
        if (!validSample) { suspendTimer.stop(); return; }
        // Rearm only after a meaningful recovery, avoiding threshold chatter.
        if (percentage >= settings.suspendPercentage + 2) suspendIssued = false;
        if (percentage > settings.lowBatteryPercentage + 2) { reset(); return; }
        const stage = percentage < settings.suspendPercentage ? 3
            : percentage <= settings.criticalBatteryPercentage ? 2
            : percentage <= settings.lowBatteryPercentage ? 1 : 0;
        if (stage < 3 && (suspendTimer.running || alertedStage === 3)) {
            suspendTimer.stop();
            alertedStage = stage;
            if (stage) alertRequested(stage === 2 ? "critical" : "low", Math.floor(percentage));
            else cleared();
        }
        if (stage > alertedStage) {
            alertedStage = stage;
            alertRequested(stage === 3 ? "suspend" : stage === 2 ? "critical" : "low", Math.floor(percentage));
        }
        if (stage === 3 && !suspendIssued && !suspendTimer.running) suspendTimer.start();
    }
    function suspendFailed() { alertRequested("failed", Math.floor(percentage)); }
    onReadyChanged: Qt.callLater(evaluate)
    onPresentChanged: Qt.callLater(evaluate)
    onOnBatteryChanged: Qt.callLater(evaluate)
    onPercentageChanged: Qt.callLater(evaluate)
    onSettingsChanged: Qt.callLater(evaluate)
    Component.onCompleted: Qt.callLater(evaluate)
    Timer {
        id: suspendTimer
        interval: monitor.suspendDelay
        onTriggered: {
            // Recheck power and the unrounded sample immediately before acting.
            if (!monitor.validSample || !monitor.validSettings || !monitor.onBattery
                    || monitor.percentage >= monitor.settings.suspendPercentage || monitor.suspendIssued) return;
            monitor.suspendIssued = true;
            monitor.alertRequested("suspending", Math.floor(monitor.percentage));
            monitor.suspendRequested();
        }
    }
}
