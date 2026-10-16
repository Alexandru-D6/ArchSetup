import QtQuick
import QtTest
import "../../../roles/desktop/files/shell"

Item {
    id: fixture
    width: 1000; height: 800
    TimePopupSurface {
        id: popup
        anchors.fill: parent
        onDismissed: visible = false
        TimeCenter { id: center; anchors.fill: parent; onClosed: popup.dismissed() }
    }
    SignalSpy { id: dismissal; target: popup; signalName: "dismissed" }
    TestCase {
        name: "TimePopup"
        when: windowShown
        function init() { popup.visible = true; popup.bottomBar = false; center.currentPage = 3; dismissal.clear(); wait(300); }
        function test_outside_presses_close_data() {
            return [{tag: "left", x: 10, y: 250}, {tag: "right", x: 990, y: 250},
                    {tag: "above", x: 500, y: 10}, {tag: "below", x: 500, y: 790}];
        }
        function test_outside_presses_close(data) {
            mousePress(popup, data.x, data.y);
            compare(dismissal.count, 1);
            verify(!popup.visible);
            mouseRelease(fixture, data.x, data.y);
        }
        function test_empty_inside_space_and_controls_stay_open() {
            mouseClick(center, 5, 90);
            compare(dismissal.count, 0);
            const arrow = findChild(findChild(center, "timer-minutes"), "increase");
            const before = center.timerMinutes;
            mouseClick(arrow);
            compare(center.timerMinutes, before + 1);
            compare(dismissal.count, 0);
            verify(popup.visible);
        }
        function test_escape_closes_with_pointer_outside() {
            center.forceActiveFocus();
            mouseMove(popup, 5, 700);
            keyClick(Qt.Key_Escape);
            compare(dismissal.count, 1);
            verify(!popup.visible);
        }
        function test_outside_press_with_timezone_picker_open() {
            center.currentPage = 2;
            center.timezoneTimes = {"UTC": {hour: 12, minute: 30}};
            wait(300);
            const picker = findChild(center, "timezone-picker");
            mouseClick(picker, picker.width - 12, picker.height / 2);
            tryCompare(picker.popup, "visible", true);
            mouseClick(popup, 5, 700);
            compare(dismissal.count, 1);
            verify(!popup.visible);
        }
        function test_bottom_bar_placement_and_dismissal() {
            popup.bottomBar = true; wait(10);
            compare(popup.cardItem.y + popup.cardItem.height, popup.height - 46);
            mouseClick(popup, 500, 790);
            compare(dismissal.count, 1);
        }
    }
}
