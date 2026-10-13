import QtQuick
import QtTest
import "../../../roles/desktop/files/shell"

Rectangle {
    id: fixture
    width: 1024
    height: 768
    color: menu.light ? "#fff8fc" : "#141313"

    SessionMenu {
        id: menu
        anchors.fill: parent
        visible: false
        reducedMotion: true
        onCancelled: visible = false
    }
    SignalSpy { id: activation; target: menu; signalName: "activated" }
    SignalSpy { id: cancellation; target: menu; signalName: "cancelled" }

    TestCase {
        name: "SessionMenu"
        when: windowShown

        function init() {
            fixture.width = 1024;
            fixture.height = 768;
            menu.canFirmwareSetup = true;
            menu.light = false;
            menu.textColor = "#e6e1e1";
            menu.visible = true;
            menu.select("lock");
            mouseMove(menu, 1, 1);
            menu.forceActiveFocus();
            activation.clear();
            cancellation.clear();
            tryCompare(menu, "activeFocus", true);
        }
        function cleanup() { menu.visible = false; }

        function test_shutdown_waits_for_selection() {
            menu.select("poweroff");
            compare(menu.selectedAction, "poweroff");
            compare(activation.count, 0);
            keyClick(Qt.Key_Return);
            compare(activation.count, 1);
            compare(activation.signalArguments[0][0], "poweroff");
            keyClick(Qt.Key_Return);
            compare(activation.count, 1);
        }
        function test_opening_preserves_requested_selection_under_pointer() {
            const button = findChild(menu, "session-lock");
            const point = button.mapToItem(fixture, button.width / 2, button.height / 2);
            menu.visible = false;
            mouseMove(fixture, point.x, point.y);
            menu.select("poweroff");
            menu.visible = true;
            waitForRendering(menu);
            compare(menu.selectedAction, "poweroff");
            compare(activation.count, 0);
        }
        function test_escape_cancels() {
            menu.select("poweroff");
            keyClick(Qt.Key_Escape);
            compare(cancellation.count, 1);
            compare(activation.count, 0);
            compare(menu.visible, false);
        }
        function test_background_click_cancels() {
            menu.select("poweroff");
            mouseClick(menu, 10, 10);
            compare(cancellation.count, 1);
            compare(activation.count, 0);
        }
        function test_arrow_and_tab_navigation() {
            keyClick(Qt.Key_Right);
            compare(menu.selectedAction, "suspend");
            keyClick(Qt.Key_Down);
            compare(menu.selectedAction, "poweroff");
            keyClick(Qt.Key_Up);
            compare(menu.selectedAction, "suspend");
            keyClick(Qt.Key_Left);
            keyClick(Qt.Key_Down);
            compare(menu.selectedAction, "settings");
            keyClick(Qt.Key_Right);
            compare(menu.selectedAction, "poweroff");
            keyClick(Qt.Key_Right);
            compare(menu.selectedAction, "reboot");
            keyClick(Qt.Key_Right);
            compare(menu.selectedAction, "firmware-setup");
            keyClick(Qt.Key_Tab);
            compare(menu.selectedAction, "lock");
            keyClick(Qt.Key_Backtab);
            compare(menu.selectedAction, "firmware-setup");
            compare(activation.count, 0);
        }
        function test_unavailable_firmware_setup_is_skipped() {
            menu.canFirmwareSetup = false;
            menu.select("firmware-setup");
            compare(menu.selectedAction, "lock");
            keyClick(Qt.Key_Left);
            compare(menu.selectedAction, "reboot");
            menu.select("task-manager");
            keyClick(Qt.Key_Down);
            compare(menu.selectedAction, "task-manager");
            const button = findChild(menu, "session-firmware-setup");
            compare(button.enabled, false);
            mouseClick(button, button.width / 2, button.height / 2);
            compare(activation.count, 0);
        }
        function test_firmware_setup_becoming_unavailable_resets_selection() {
            menu.select("firmware-setup");
            menu.canFirmwareSetup = false;
            compare(menu.selectedAction, "lock");
            compare(activation.count, 0);
        }
        function test_each_tile_activates_data() {
            return ["lock", "suspend", "logout", "task-manager", "settings", "poweroff", "reboot", "firmware-setup"]
                .map(action => ({tag: action, action: action}));
        }
        function test_each_tile_activates(data) {
            const button = findChild(menu, "session-" + data.action);
            verify(button !== null);
            mouseMove(button, button.width / 2, button.height / 2);
            compare(menu.selectedAction, data.action);
            mouseClick(button, button.width / 2, button.height / 2);
            compare(activation.count, 1);
            compare(activation.signalArguments[0][0], data.action);
            mouseClick(button, button.width / 2, button.height / 2);
            compare(activation.count, 1);
        }
        function test_reopening_starts_a_new_selection() {
            keyClick(Qt.Key_Return);
            menu.visible = false;
            menu.select("poweroff");
            menu.visible = true;
            menu.forceActiveFocus();
            keyClick(Qt.Key_Return);
            compare(activation.count, 2);
            compare(activation.signalArguments[1][0], "poweroff");
        }
        function test_icons_and_theme_rendering() {
            menu.select("poweroff");
            waitForRendering(menu);
            for (const choice of menu.choices) {
                const button = findChild(menu, "session-" + choice.action);
                const image = grabImage(findChild(button, "session-icon"));
                let painted = false;
                for (let x = 0; x < image.width && !painted; x++) {
                    for (let y = 0; y < image.height; y++) {
                        if (image.alpha(x, y) > 0) { painted = true; break; }
                    }
                }
                verify(painted, choice.action + " icon did not render");
            }
            const dark = grabImage(fixture);
            dark.save("/tmp/archsetup-session-dark.png");
            menu.light = true;
            menu.textColor = "#1d1b20";
            waitForRendering(menu);
            const light = grabImage(fixture);
            verify(!light.equals(dark));
            light.save("/tmp/archsetup-session-light.png");
        }
        function test_small_screen_keeps_all_tiles_inside() {
            fixture.width = 320;
            fixture.height = 240;
            waitForRendering(menu);
            for (const choice of menu.choices) {
                const button = findChild(menu, "session-" + choice.action);
                const point = button.mapToItem(menu, 0, 0);
                verify(point.x >= 0 && point.y >= 0);
                verify(point.x + button.width <= menu.width);
                verify(point.y + button.height <= menu.height);
            }
        }
    }
}
