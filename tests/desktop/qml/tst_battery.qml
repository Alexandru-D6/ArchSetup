import QtQuick
import QtTest
import "../../../roles/desktop/files/shell"

TestCase {
    id: test
    name: "Battery"
    when: windowShown
    BatteryMonitor { id: battery; suspendDelay: 80 }
    SignalSpy { id: alerts; target: battery; signalName: "alertRequested" }
    SignalSpy { id: sleeps; target: battery; signalName: "suspendRequested" }
    function init() {
        battery.ready = false;
        battery.present = true;
        battery.onBattery = true;
        battery.percentage = 80;
        battery.settings = {lowBatteryPercentage: 20, criticalBatteryPercentage: 10, suspendPercentage: 3};
        battery.reset();
        battery.ready = true;
        wait(1);
        alerts.clear(); sleeps.clear();
    }
    function test_alerts_escalate_once_and_rearm_after_charge() {
        battery.percentage = 20;
        tryCompare(alerts, "count", 1);
        compare(alerts.signalArguments[0][0], "low");
        battery.percentage = 19; wait(5); compare(alerts.count, 1);
        battery.percentage = 10;
        tryCompare(alerts, "count", 2);
        compare(alerts.signalArguments[1][0], "critical");
        battery.percentage = 10.1; wait(5);
        battery.percentage = 10; wait(5); compare(alerts.count, 2);
        battery.onBattery = false; wait(5);
        battery.onBattery = true;
        tryCompare(alerts, "count", 3);
        compare(alerts.signalArguments[2][0], "critical");
    }
    function test_exact_boundary_does_not_suspend_and_resume_does_not_loop() {
        battery.percentage = 3;
        wait(120); compare(sleeps.count, 0); compare(battery.suspendPending, false);
        battery.percentage = 2.99;
        tryCompare(battery, "suspendPending", true);
        compare(alerts.signalArguments[alerts.count - 1][0], "suspend");
        tryCompare(sleeps, "count", 1);
        compare(alerts.signalArguments[alerts.count - 1][0], "suspending");
        battery.percentage = 2.5; wait(120); compare(sleeps.count, 1);
        battery.percentage = 2; wait(120); compare(sleeps.count, 1);
        battery.suspendFailed();
        compare(alerts.signalArguments[alerts.count - 1][0], "failed");
        wait(120); compare(sleeps.count, 1);
    }
    function test_unlock_repeats_the_current_low_or_critical_warning() {
        battery.percentage = 18.9;
        tryCompare(alerts, "count", 1);
        battery.remind();
        compare(alerts.count, 2);
        compare(alerts.signalArguments[1][0], "low");
        compare(alerts.signalArguments[1][1], 18);
        battery.remind(); compare(alerts.count, 3);
        battery.percentage = 9;
        tryCompare(alerts, "count", 4);
        battery.remind();
        compare(alerts.count, 5);
        compare(alerts.signalArguments[4][0], "critical");
        compare(battery.alertedStage, 2);
    }
    function test_unlock_waits_for_valid_data_without_duplicate_initial_alerts() {
        battery.ready = false;
        battery.percentage = 15;
        battery.remind();
        compare(alerts.count, 0);
        compare(battery.reminderPending, true);
        battery.ready = true;
        tryCompare(alerts, "count", 1);
        wait(10); compare(alerts.count, 1);
        compare(battery.reminderPending, false);
    }
    function test_unlock_skips_healthy_charging_missing_and_invalid_batteries() {
        battery.remind(); compare(alerts.count, 0);
        battery.onBattery = false;
        battery.percentage = 15;
        battery.remind(); compare(alerts.count, 0);
        battery.onBattery = true;
        battery.present = false;
        battery.remind(); compare(alerts.count, 0);
        battery.present = true;
        battery.percentage = NaN;
        battery.remind(); compare(alerts.count, 0);
        wait(10); compare(alerts.count, 0);
    }
    function test_unlock_does_not_repeat_automatic_suspend_after_resume() {
        battery.percentage = 2;
        tryCompare(battery, "suspendPending", true);
        battery.remind();
        compare(battery.suspendPending, true);
        tryCompare(sleeps, "count", 1);
        battery.remind();
        compare(alerts.signalArguments[alerts.count - 1][0], "critical");
        compare(battery.suspendIssued, true);
        compare(battery.suspendPending, false);
        wait(120); compare(sleeps.count, 1);
    }
    function test_connecting_power_cancels_pending_suspend() {
        battery.percentage = 2;
        tryCompare(battery, "suspendPending", true);
        battery.onBattery = false;
        tryCompare(battery, "suspendPending", false);
        wait(120); compare(sleeps.count, 0);
    }
    function test_recovery_and_settings_changes_cancel_pending_suspend() {
        battery.settings = {lowBatteryPercentage: 30, criticalBatteryPercentage: 15, suspendPercentage: 5};
        battery.percentage = 4;
        tryCompare(battery, "suspendPending", true);
        battery.settings = {lowBatteryPercentage: 30, criticalBatteryPercentage: 15, suspendPercentage: 3};
        tryCompare(battery, "suspendPending", false);
        compare(alerts.signalArguments[alerts.count - 1][0], "critical");
        wait(120); compare(sleeps.count, 0);
    }
    function test_absent_unready_and_invalid_readings_never_suspend() {
        battery.present = false; battery.percentage = 0;
        wait(120); compare(sleeps.count, 0); compare(alerts.count, 0);
        battery.present = true; battery.ready = false;
        wait(120); compare(sleeps.count, 0);
        battery.percentage = NaN; battery.ready = true;
        wait(120); compare(sleeps.count, 0);
        battery.percentage = -1; wait(120); compare(sleeps.count, 0);
        battery.percentage = 2;
        battery.settings = {lowBatteryPercentage: 10, criticalBatteryPercentage: 20, suspendPercentage: 3};
        wait(120); compare(sleeps.count, 0);
    }
}
