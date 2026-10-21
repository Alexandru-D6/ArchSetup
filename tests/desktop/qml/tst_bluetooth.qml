import QtQuick
import QtTest
import "../../../roles/desktop/files/shell"

Item {
    width: 420; height: 900
    ControlCenter { id: testTheme; visible: false }
    BluetoothPanel { id: panel; theme: testTheme; width: 380; anchors.centerIn: parent }
    SignalSpy { id: control; target: panel; signalName: "controlRequested" }
    TestCase {
        name: "BluetoothPanel"
        when: windowShown
        function init() {
            panel.ready = true; panel.busy = false; panel.prompt = null; panel.error = ""; panel.operation = "";
            panel.selectedId = ""; panel.visible = true;
            panel.snapshot = {bluetoothAvailable: true, bluetoothEnabled: true, bluetoothAdapter: "/org/bluez/hci0",
                bluetoothAdapters: [{id: "/org/bluez/hci0", name: "Laptop"}, {id: "/org/bluez/hci1", name: "USB"}],
                bluetoothDevices: [{id: "headphones", address: "AA:BB:CC:DD:EE:01", name: "Headphones", paired: true, connected: true, trusted: true, battery: 80},
                    {id: "keyboard", address: "AA:BB:CC:DD:EE:02", name: "Keyboard", paired: false, connected: false, battery: -1}]};
            control.clear(); wait(20);
        }
        function test_pair_connect_disconnect_and_forget() {
            mouseClick(findChild(panel, "bluetooth-device-AA:BB:CC:DD:EE:02"));
            compare(findChild(panel, "bluetooth-connect").text, "Pair and connect");
            mouseClick(findChild(panel, "bluetooth-connect"));
            compare(Array.from(control.signalArguments[0]), ["pair", "keyboard"]);
            mouseClick(findChild(panel, "bluetooth-device-AA:BB:CC:DD:EE:01"));
            mouseClick(findChild(panel, "bluetooth-connect"));
            compare(Array.from(control.signalArguments[1]), ["disconnect", "headphones"]);
            mouseClick(findChild(panel, "bluetooth-forget")); compare(control.count, 2);
            mouseClick(findChild(panel, "bluetooth-forget-cancel")); compare(control.count, 2);
            mouseClick(findChild(panel, "bluetooth-forget")); mouseClick(findChild(panel, "bluetooth-forget-confirm"));
            compare(Array.from(control.signalArguments[2]), ["forget", "headphones"]);
        }
        function test_pairing_confirmation_and_rejection() {
            panel.busy = true; panel.operation = "pair";
            panel.prompt = {kind: "confirm", code: "000123", name: "Keyboard"};
            compare(findChild(panel, "bluetooth-pairing-code").text, "000123");
            verify(!findChild(panel, "bluetooth-connect").enabled);
            mouseClick(findChild(panel, "bluetooth-confirm"));
            compare(Array.from(control.signalArguments[0]), ["respond", true]);
            mouseClick(findChild(panel, "bluetooth-reject"));
            compare(Array.from(control.signalArguments[1]), ["cancel", null]);
        }
        function test_pin_and_passkey_validation_and_clearing() {
            panel.prompt = {kind: "passkey", name: "Keyboard"};
            const code = findChild(panel, "bluetooth-code");
            verify(!findChild(panel, "bluetooth-confirm").enabled);
            code.text = "abc"; verify(!findChild(panel, "bluetooth-confirm").enabled);
            code.text = "000123"; wait(20); mouseClick(findChild(panel, "bluetooth-confirm"));
            compare(Array.from(control.signalArguments[0]), ["respond", "000123"]); compare(code.text, "");
            panel.prompt = {kind: "pin", name: "Old keyboard"}; code.text = "A1B2"; wait(20);
            mouseClick(findChild(panel, "bluetooth-confirm"));
            compare(Array.from(control.signalArguments[1]), ["respond", "A1B2"]); compare(code.text, "");
            code.text = "secret"; panel.visible = false; compare(code.text, "");
        }
        function test_display_code_can_cancel_without_confirmation() {
            panel.busy = true; panel.operation = "pair";
            panel.prompt = {kind: "display", code: "123456", name: "Keyboard", entered: 2};
            verify(!findChild(panel, "bluetooth-confirm").visible);
            verify(findChild(panel, "bluetooth-prompt").text.includes("press Enter"));
            mouseClick(findChild(panel, "bluetooth-cancel"));
            compare(Array.from(control.signalArguments[0]), ["cancel", null]);
        }
        function test_power_scan_adapter_and_busy_state() {
            mouseClick(findChild(panel, "bluetooth-power"));
            compare(Array.from(control.signalArguments[0]), ["power", false]);
            mouseClick(findChild(panel, "bluetooth-scan"));
            compare(Array.from(control.signalArguments[1]), ["scan", true]);
            findChild(panel, "bluetooth-adapter").forceActiveFocus(); keyClick(Qt.Key_Down);
            compare(Array.from(control.signalArguments[2]), ["select", "/org/bluez/hci1"]);
            panel.busy = true; control.clear();
            mouseClick(findChild(panel, "bluetooth-power")); mouseClick(findChild(panel, "bluetooth-scan"));
            compare(control.count, 0);
        }
        function test_missing_hardware_and_error_are_visible() {
            panel.snapshot = {bluetoothAvailable: false, bluetoothError: "No adapter"};
            compare(findChild(panel, "bluetooth-error").text, "No adapter");
            verify(!findChild(panel, "bluetooth-power").enabled);
            panel.error = "Permission denied";
            compare(findChild(panel, "bluetooth-error").text, "Permission denied");
        }
    }
}
