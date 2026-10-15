import QtQuick
import QtTest
import "../../../roles/desktop/files/lock"

Rectangle {
    id: fixture
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
        function init() {
            fixture.width = 1024; fixture.height = 768;
            screen.clockPosition = null;
            screen.dateCaption = "Thursday, October 15";
            screen.controls.clearPassword();
        }
        function test_placement_stays_clear_of_password_controls_data() {
            return [
                {tag: "default", width: 1920, height: 1080, position: null},
                {tag: "scaled top left", width: 1920, height: 1080, position: {x: 0, y: 0}},
                {tag: "bottom right", width: 1280, height: 800, position: {x: 1, y: 1}},
                {tag: "small bottom", width: 800, height: 600, position: {x: 0.5, y: 1}},
                {tag: "portrait", width: 720, height: 1280, position: {x: 1, y: 1}},
                {tag: "minimum", width: 320, height: 240, position: {x: 0.5, y: 1}}
            ];
        }
        function test_placement_stays_clear_of_password_controls(data) {
            fixture.width = data.width; fixture.height = data.height;
            screen.clockPosition = data.position;
            waitForRendering(screen);
            const group = findChild(screen, "lock-clock-group");
            const controls = screen.controls;
            if (group.visible) {
                verify(group.x >= 16);
                verify(group.y >= 64);
                verify(group.x + group.width <= screen.width - 16);
                verify(group.y + group.height <= controls.y - 20);
            }
            const input = findChild(screen, "lock-password");
            controls.focusPassword();
            keyClick(Qt.Key_A);
            compare(input.text, "a");
            compare(findChild(screen, "lock-clock-date").text, "Thursday, October 15");
        }

        function verifyFrame(clock, color) {
            const frame = grabImage(screen);
            const center = clock.mapToItem(screen, clock.width / 2, clock.height / 2);
            const x = Math.floor(center.x);
            const y = Math.floor(center.y);
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
