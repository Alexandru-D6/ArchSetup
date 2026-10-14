import QtQuick
import QtTest
import "../../../roles/desktop/files/lock"

Rectangle {
    width: 1024
    height: 768
    LockScreen {
        id: screen
        anchors.fill: parent
    }
    TestCase {
        name: "LockClock"
        when: windowShown
        property string server: "http://127.0.0.1:0"

        function verifyFrame(clock, color) {
            const frame = grabImage(clock);
            const x = Math.floor(frame.width / 2);
            const y = Math.floor(frame.height / 2);
            compare(frame.alpha(x, y), 255);
            compare(frame.red(x, y), color[0]);
            compare(frame.green(x, y), color[1]);
            compare(frame.blue(x, y), color[2]);
        }
        function test_clock_keeps_previous_frame_visible_while_loading() {
            const clock = findChild(screen, "lock-clock");
            const input = findChild(screen, "lock-password");
            const colors = [[255, 0, 0], [0, 255, 0], [0, 0, 255]];
            clock.source = server + "/frame-0.png";
            tryCompare(clock, "status", Image.Ready);
            verify(waitForRendering(clock));
            verifyFrame(clock, colors[0]);

            for (let revision = 1; revision < colors.length; revision++) {
                // The local fixture delays replacement frames so Loading spans
                // several rendered frames, independently of disk/decode speed.
                clock.source = server + "/frame-" + revision + ".png";
                compare(clock.status, Image.Loading);
                screen.controls.focusPassword();
                keyClick(Qt.Key_A);
                compare(input.text.length, revision);
                for (let sample = 0; sample < 3; sample++) {
                    compare(clock.status, Image.Loading);
                    verifyFrame(clock, colors[revision - 1]);
                    compare(clock.status, Image.Loading);
                    wait(30);
                }
                tryCompare(clock, "status", Image.Ready);
                verify(waitForRendering(clock));
                verifyFrame(clock, colors[revision]);
            }
        }
    }
}
