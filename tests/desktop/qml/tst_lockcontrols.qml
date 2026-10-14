import QtQuick
import QtTest
import "../../../roles/desktop/files/lock"

Rectangle {
    id: fixture
    width: 1024
    height: 300
    color: "#191620"
    LockControls {
        id: controls
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        height: implicitHeight
    }
    SignalSpy { id: submission; target: controls; signalName: "submitted" }
    SignalSpy { id: power; target: controls; signalName: "powerPressed" }

    TestCase {
        name: "LockControls"
        when: windowShown
        function input() { return findChild(controls, "lock-password"); }
        function mask() { return findChild(controls, "lock-password-shapes"); }
        function init() {
            fixture.width = 1024;
            fixture.height = 300;
            controls.username = "alex";
            controls.layout = "US · Euro";
            controls.fontSize = 12;
            controls.reducedMotion = true;
            controls.busy = false;
            controls.message = "";
            controls.prompt = "Enter password";
            controls.poweroffLabel = "Power off";
            controls.rebootLabel = "Reboot";
            controls.clearPassword();
            controls.focusPassword();
            submission.clear();
            power.clear();
            tryCompare(input(), "activeFocus", true);
            waitForRendering(controls);
        }
        function test_typing_and_editing_keep_existing_shapes() {
            keyClick(Qt.Key_A);
            keyClick(Qt.Key_B);
            keyClick(Qt.Key_C);
            compare(mask().count, 3);
            compare(mask().shapes.length, 3);
            const first = mask().shapes.slice();
            keyClick(Qt.Key_Backspace);
            compare(mask().count, 2);
            compare(mask().shapes, first.slice(0, 2));
            keyClick(Qt.Key_D);
            compare(mask().shapes.slice(0, 2), first.slice(0, 2));
            for (const shape of mask().shapes) verify(shape >= 0 && shape < 6);
            keyClick(Qt.Key_Escape);
            compare(mask().count, 0);
            compare(submission.count, 0);
        }
        function test_submit_clears_response_and_busy_prevents_duplicates() {
            input().text = "dummy response";
            keyClick(Qt.Key_Return);
            compare(submission.count, 1);
            compare(submission.signalArguments[0][0], "dummy response");
            compare(input().text, "");
            compare(mask().count, 0);
            controls.busy = true;
            keyClick(Qt.Key_Return);
            mouseClick(findChild(controls, "lock-submit"));
            compare(submission.count, 1);
            controls.busy = false;
            tryCompare(input(), "activeFocus", true);
        }
        function test_layout_scrolls_and_rapid_switches_finish_on_latest() {
            controls.reducedMotion = false;
            const label = findChild(controls, "lock-layout");
            controls.layout = "US · AltGr";
            compare(label.previousText, "US · Euro");
            compare(label.currentText, "US · AltGr");
            verify(label.animating);
            wait(40);
            verify(label.progress > 0 && label.progress < 1);
            controls.layout = "ES";
            controls.layout = "DE · Intl";
            tryCompare(label, "animating", false);
            compare(label.progress, 1);
            compare(label.currentText, "DE · Intl");
            controls.reducedMotion = true;
            controls.layout = "US";
            verify(!label.animating);
            compare(label.progress, 1);
            compare(label.currentText, "US");
        }
        function test_pills_resize_with_text_and_font_and_keep_padding() {
            const identity = findChild(controls, "lock-identity");
            const button = findChild(controls, "lock-reboot");
            const initialIdentity = identity.width;
            controls.layout = "A longer keyboard layout";
            tryVerify(() => identity.width > initialIdentity);
            const initialButton = button.width;
            controls.rebootLabel = "Confirm restart";
            tryVerify(() => button.width > initialButton);
            const caption = findChild(button, "lock-power-caption");
            verify(button.width >= caption.implicitWidth + 32);
            const beforeFont = button.width;
            controls.fontSize = 20;
            tryVerify(() => button.width > beforeFont);
            verify(button.height >= caption.implicitHeight + 20);
            const password = findChild(controls, "lock-password-pill");
            controls.prompt = "Enter your authentication response";
            waitForRendering(controls);
            const promptWidth = password.width;
            controls.prompt = "Password";
            tryVerify(() => password.width < promptWidth);
            input().text = "01234567890123456789";
            tryVerify(() => password.width >= mask().implicitWidth + 80);
        }
        function test_confirmation_clicks_keep_password_focus() {
            const button = findChild(controls, "lock-poweroff");
            mouseClick(button);
            compare(power.count, 1);
            compare(power.signalArguments[0][0], "poweroff");
            controls.poweroffLabel = "Confirm";
            controls.rebootLabel = "Cancel";
            mouseClick(findChild(controls, "lock-reboot"));
            compare(power.count, 2);
            compare(power.signalArguments[1][0], "reboot");
            tryCompare(input(), "activeFocus", true);
        }
        function test_small_screen_wraps_long_labels_and_password() {
            fixture.width = 320;
            controls.username = "a very long desktop username";
            controls.layout = "A long keyboard layout variant";
            controls.rebootLabel = "A lengthy confirmation label";
            input().text = "0123456789".repeat(10);
            waitForRendering(controls);
            for (const name of ["identity", "password-pill", "poweroff", "reboot"]) {
                const pill = findChild(controls, "lock-" + name);
                const point = pill.mapToItem(fixture, 0, 0);
                verify(point.x >= 16, name + " crossed left padding");
                verify(point.x + pill.width <= fixture.width - 16, name + " crossed right padding");
                verify(point.y >= 0 && point.y + pill.height <= fixture.height - 20, name + " crossed vertical edges");
            }
        }
        function test_all_shapes_render_and_response_stays_hidden() {
            input().text = "dummy!";
            mask().shapes = [0, 1, 2, 3, 4, 5];
            waitForRendering(controls);
            const image = grabImage(mask());
            for (let index = 0; index < 6; index++) {
                let painted = false;
                for (let x = index * 20; x < index * 20 + 16 && !painted; x++) {
                    for (let y = 0; y < image.height; y++) {
                        if (image.alpha(x, y) > 0) { painted = true; break; }
                    }
                }
                verify(painted, "Shape " + index + " was empty");
            }
            verify(input().displayText.indexOf("dummy") < 0);
            grabImage(fixture).save("/tmp/archsetup-lock-controls.png");
        }
    }
}
