import QtQuick
import QtTest
import "../../../roles/desktop/files/shared"

Rectangle {
    id: fixture
    width: 480; height: 240
    color: "#21161c"
    Image {
        anchors.fill: parent
        source: Qt.resolvedUrl("../../../roles/desktop/files/assets/desktop-wallpaper.jpg")
        fillMode: Image.PreserveAspectCrop
    }
    BatteryIndicator { id: badge; x: 16; y: 16 }
    TextInput { id: password; x: 16; y: 190; width: 200; height: 32; echoMode: TextInput.Password }
    SignalSpy { id: clicked; target: badge; signalName: "clicked" }
    TestCase {
        name: "BatteryIndicator"
        when: windowShown
        function init() {
            password.forceActiveFocus();
            badge.present = true; badge.percentage = 42; badge.charging = false; badge.pluggedIn = false;
            badge.interactive = false; password.clear(); password.forceActiveFocus(); clicked.clear();
            badge.fullyCharged = false;
        }
        function test_power_states_update_label_and_highlight() {
            compare(badge.label, "42%"); compare(badge.color, badge.surface);
            badge.charging = true; badge.pluggedIn = true;
            compare(badge.label, "Charging · 42%"); compare(badge.color, badge.accent);
            waitForRendering(badge);
            const caption = findChild(badge, "battery-label");
            verify(!caption.truncated, "Caption width " + caption.width + ", required " + caption.implicitWidth + ", badge " + badge.width);
            compare(findChild(badge, "battery-power-icon").visible, true);
            badge.percentage = 43; compare(badge.label, "Charging · 43%");
            badge.charging = false; compare(badge.label, "Plugged in · 43%");
            badge.fullyCharged = true; compare(badge.label, "Charged · 43%");
            badge.fullyCharged = false;
            badge.percentage = 100; compare(badge.label, "Charged · 100%");
            badge.pluggedIn = false; compare(badge.label, "100%");
            compare(findChild(badge, "battery-power-icon").visible, false);
        }
        function test_charging_does_not_take_password_focus() {
            keyClick(Qt.Key_A);
            badge.charging = true; badge.pluggedIn = true;
            mouseClick(badge);
            compare(clicked.count, 0);
            compare(password.activeFocus, true);
            keyClick(Qt.Key_B); compare(password.text, "ab");
            waitForRendering(badge);
            grabImage(fixture).save("/tmp/archsetup-charging-indicator.png");
        }
        function test_desktop_badge_opens_controls_by_mouse_and_keyboard() {
            badge.interactive = true;
            mouseClick(badge); compare(clicked.count, 1);
            badge.forceActiveFocus(); keyClick(Qt.Key_Return); compare(clicked.count, 2);
        }
        function test_missing_or_invalid_battery_is_hidden() {
            badge.present = false; compare(badge.visible, false);
            badge.present = true; badge.percentage = NaN; compare(badge.visible, false);
            badge.percentage = -1; compare(badge.visible, false);
            badge.percentage = 101; compare(badge.visible, false);
        }
    }
}
