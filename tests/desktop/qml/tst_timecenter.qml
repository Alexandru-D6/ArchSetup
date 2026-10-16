import QtQuick
import QtTest
import "../../../roles/desktop/files/shell"

Item {
    width: 580; height: 600
    TimeCenter { id: center; anchors.fill: parent }
    SignalSpy { id: dismissal; target: center; signalName: "closed" }
    SignalSpy { id: completion; target: center; signalName: "timerCompleted" }
    TestCase {
        name: "TimeCenter"
        when: windowShown
        function init() {
            center.currentPage = 0; center.calendarMode = "days";
            center.timerRunning = false; center.timerRemaining = 0; center.timerFinished = false;
            center.stopwatchRunning = false; center.stopwatchElapsed = 0;
            center.showCompleted = false;
            center.lastWheelChange = 0;
            wait(300);
        }
        function test_heading_single_then_year_then_month() {
            center.month = new Date(2024, 3, 1);
            const heading = findChild(center, "calendar-heading");
            mouseClick(heading);
            tryCompare(center, "calendarMode", "years");
            center.pickYear(2032);
            compare(center.calendarMode, "months");
            center.pickMonth(8);
            compare(center.calendarMode, "days");
            compare(center.month.getFullYear(), 2032);
            compare(center.month.getMonth(), 8);
            mouseClick(heading);
            tryCompare(center, "calendarMode", "years");
        }
        function test_heading_double_click_today() {
            center.month = new Date(2000, 0, 1);
            mouseDoubleClickSequence(findChild(center, "calendar-heading"));
            wait(450);
            compare(center.calendarMode, "days");
            compare(center.selectedDay, center.dayKey(new Date()));
            compare(center.month.getMonth(), new Date().getMonth());
        }
        function test_pending_completed_views_keep_task_identity() {
            center.currentPage = 1;
            center.tasks = [{text: "Finished", day: "", done: true}, {text: "Pending", day: "", done: false}, {text: "Calendar", day: "2026-10-16", done: false}];
            const list = findChild(center, "todo-list");
            tryCompare(list, "count", 1);
            compare(list.model[0].sourceIndex, 1);
            center.showCompleted = true;
            tryCompare(list, "count", 1);
            compare(list.model[0].sourceIndex, 0);
            center.changeTask(0, false);
            tryCompare(list, "count", 0);
            center.currentPage = 2;
            center.currentPage = 1;
            verify(!center.showCompleted);
            tryCompare(list, "count", 2);
        }
        function test_timezone_picker_uses_theme_and_selects() {
            center.currentPage = 2; wait(300);
            center.timezoneTimes = {"UTC": {hour: 12, minute: 30}, "Asia/Kathmandu": {hour: 18, minute: 15}};
            const picker = findChild(center, "timezone-picker");
            compare(picker.background.color, center.surface);
            mouseClick(picker, picker.width - 12, picker.height / 2);
            tryCompare(picker.popup, "visible", true);
            compare(picker.popup.background.color, center.surface);
            const options = picker.popup.contentItem;
            tryVerify(() => options.itemAtIndex(1) !== null);
            mouseClick(options.itemAtIndex(1));
            tryCompare(picker.popup, "visible", false);
            compare(picker.currentText, "Asia/Kathmandu");
        }
        function test_vertical_wheel_scrolls_tasks() {
            center.currentPage = 1;
            center.tasks = Array.from({length: 60}, (_, index) => ({text: "Task " + index, day: "", done: false}));
            wait(300);
            const list = findChild(center, "todo-list");
            list.contentY = 0;
            mouseWheel(list, 100, 100, 0, -120);
            tryVerify(() => list.contentY > 0);
            compare(center.currentPage, 1);
        }
        function test_world_clocks_validation_and_removal() {
            center.timezoneTimes = {"UTC": {hour: 12, minute: 30}, "Asia/Kathmandu": {hour: 18, minute: 15}};
            center.zones = [];
            center.addZone("UTC"); center.addZone("UTC"); center.addZone("Invalid/Zone"); center.addZone("Asia/Kathmandu");
            compare(center.zones.length, 2);
            center.currentPage = 2; wait(30);
            center.removeZone("UTC");
            compare(center.zones[0], "Asia/Kathmandu");
        }
        function test_timer_number_single_click_edit() {
            center.currentPage = 3; wait(300);
            const minutes = findChild(center, "timer-minutes");
            const input = findChild(minutes, "timer-number-input");
            center.timerMinutes = 5;
            mouseClick(findChild(minutes, "increase"));
            compare(center.timerMinutes, 6);
            mouseClick(findChild(minutes, "decrease"));
            compare(center.timerMinutes, 5);
            mouseClick(input);
            keyClick(Qt.Key_1); keyClick(Qt.Key_2);
            compare(center.timerMinutes, 12);
            keyClick(Qt.Key_Tab);
            compare(input.text, "12");
            verify(center.timerRemaining === 0);
        }
        function test_stopwatch_position_does_not_follow_lap_count() {
            center.currentPage = 4; wait(300);
            const display = findChild(center, "stopwatch-display");
            const before = display.mapToItem(center, 0, 0).y;
            center.laps = [1000]; wait(30);
            compare(display.mapToItem(center, 0, 0).y, before);
            center.laps = Array(50).fill(12345); wait(30);
            compare(display.mapToItem(center, 0, 0).y, before);
            center.laps = [];
        }
        function test_matching_machine_and_utc_readouts() {
            center.currentPage = 2; wait(300);
            const local = findChild(center, "machine-clock-time");
            const utc = findChild(center, "utc-clock-time");
            verify(/^\d{2}:\d{2}:\d{2}$/.test(local.text));
            verify(/^\d{2}:\d{2}:\d{2}$/.test(utc.text));
            compare(local.mapToItem(center, 0, 0).y, utc.mapToItem(center, 0, 0).y);
            compare(local.font.pixelSize, utc.font.pixelSize);
        }
        function test_wheel_navigation_and_horizontal_swipe() {
            const rail = findChild(center, "time-navigation");
            mouseWheel(rail, 30, rail.height / 2, -120, 0);
            tryCompare(center, "currentPage", 1);
            const slider = findChild(center, "time-pages");
            tryCompare(slider, "currentIndex", 1);
            tryVerify(() => Math.abs(slider.currentItem.mapToItem(slider, 0, 0).x) < 1);
            wait(350);
            const pages = findChild(center, "time-pages");
            mouseWheel(pages, 200, 150, -120, 0);
            tryCompare(center, "currentPage", 2);
            tryCompare(pages, "currentIndex", 2);
            tryVerify(() => Math.abs(pages.currentItem.mapToItem(pages, 0, 0).x) < 1);
            wait(350);
            center.currentPage = 3; wait(300);
            mouseDrag(pages, pages.width - 25, 30, -pages.width + 50, 0, Qt.LeftButton, Qt.NoModifier, 400);
            tryCompare(center, "currentPage", 4);
            center.currentPage = 2;
            tryCompare(pages, "currentIndex", 2);
        }
        function test_drag_then_wheel_moves_actual_page_content() {
            const pages = findChild(center, "time-pages");
            center.currentPage = 0; wait(300);
            mouseDrag(pages, pages.width - 25, 30, -pages.width + 50, 0, Qt.LeftButton, Qt.NoModifier, 400);
            tryCompare(center, "currentPage", 1);
            wait(350);
            mouseWheel(pages, 200, 150, -120, 0);
            tryCompare(center, "currentPage", 2);
            tryCompare(pages, "currentIndex", 2);
            tryVerify(() => Math.abs(pages.contentItem.contentX - 2 * pages.width) < 1);
            tryVerify(() => Math.abs(pages.currentItem.mapToItem(pages, 0, 0).x) < 1);
            center.lastWheelChange = 0;
            mouseWheel(pages, 200, 150, 120, 0);
            tryCompare(pages, "currentIndex", 1);
            tryVerify(() => Math.abs(pages.contentItem.contentX - pages.width) < 1);
        }
        function test_calendar_first_task_keeps_cells_and_digits_fixed() {
            center.tasks = []; wait(30);
            const cell = findChild(center, "calendar-day-15");
            const digit = findChild(cell, "day-number");
            const width = cell.width;
            const digitX = digit.mapToItem(center, 0, 0).x;
            const digitY = digit.mapToItem(center, 0, 0).y;
            center.addTask("First task", cell.key); wait(30);
            verify(findChild(cell, "task-dot").visible);
            compare(cell.width, width);
            compare(digit.mapToItem(center, 0, 0).x, digitX);
            compare(digit.mapToItem(center, 0, 0).y, digitY);
            verify(Math.abs(findChild(center, "calendar-day-16").width - width) <= 1);
        }
        function test_timezone_arrow_centered() {
            center.currentPage = 2; wait(300);
            const picker = findChild(center, "timezone-picker");
            const arrow = findChild(center, "timezone-indicator");
            compare(arrow.y + arrow.height / 2, picker.height / 2);
        }
        function test_timer_arrow_hover_clears_after_click() {
            center.currentPage = 3; wait(300);
            const arrow = findChild(findChild(center, "timer-minutes"), "increase");
            mouseMove(arrow, arrow.width / 2, arrow.height / 2);
            mouseClick(arrow);
            mouseMove(center, 2, 2); wait(30);
            verify(!arrow.hovered);
            verify(!arrow.visualFocus);
            compare(arrow.background.color, "#00000000");
            compare(arrow.opacity, 0.55);
        }
        function test_escape_with_pointer_outside_and_field_focused() {
            center.currentPage = 3; wait(300);
            const input = findChild(findChild(center, "timer-minutes"), "timer-number-input");
            mouseClick(input);
            mouseMove(center, -10, -10);
            dismissal.clear();
            keyClick(Qt.Key_Escape);
            compare(dismissal.count, 1);
        }
        function test_navigation_is_at_top() {
            const tabs = findChild(center, "time-navigation");
            compare(tabs.mapToItem(center, 0, 0).y, 16);
            verify(tabs.height <= 45);
            verify(tabs.width > center.width - 40);
        }
        function test_vertical_wheel_scrolls_laps() {
            center.currentPage = 4;
            center.laps = Array(50).fill(12345); wait(300);
            const list = findChild(center, "stopwatch-laps");
            list.contentY = 0;
            mouseWheel(list, 100, 40, 0, -120);
            tryVerify(() => list.contentY > 0);
            compare(center.currentPage, 4);
            center.laps = [];
        }
        function test_vertical_wheel_scrolls_world_clocks() {
            center.currentPage = 2;
            center.timezoneTimes = {"UTC": {hour: 12, minute: 30}};
            center.zones = Array(12).fill("UTC"); wait(300);
            const scroll = findChild(center, "world-clock-scroll");
            scroll.contentItem.contentY = 0;
            mouseWheel(scroll, 150, 300, 0, -120);
            tryVerify(() => scroll.contentItem.contentY > 0);
            compare(center.currentPage, 2);
            center.zones = [];
        }
        function test_visual_pages() {
            center.timezoneTimes = {"Europe/Madrid": {hour: 17, minute: 25}, "Asia/Kathmandu": {hour: 21, minute: 10}};
            center.zones = ["Europe/Madrid", "Asia/Kathmandu"];
            for (let i = 0; i < 5; i++) {
                center.currentPage = i; wait(300);
                grabImage(center).save("/tmp/archsetup-time-center-" + i + ".png");
            }
        }
        function test_calendar_navigation_and_tasks() {
            center.month = new Date(2024, 0, 1);
            center.moveMonth(-1);
            compare(center.month.getFullYear(), 2023);
            compare(center.month.getMonth(), 11);
            center.tasks = [];
            center.addTask("  Daily task  ", "2024-02-29");
            center.addTask("Todo", "");
            center.addTask(" ", "");
            compare(center.tasks.length, 2);
            compare(center.tasks[0].text, "Daily task");
            center.changeTask(0, false);
            verify(center.tasks[0].done);
            center.changeTask(0, true);
            compare(center.tasks[0].text, "Todo");
        }
        function test_page_wrap() {
            center.currentPage = 0;
            center.switchPage(-1);
            compare(center.currentPage, 4);
            center.switchPage(1);
            compare(center.currentPage, 0);
            for (let i = 0; i < 5; i++) { center.currentPage = i; wait(10); }
        }
        function test_edit_paused_timer_preserves_other_parts() {
            center.timerRemaining = 3661250;
            center.setTimerPart("timerMinutes", 20);
            compare(center.timerHours, 1);
            compare(center.timerMinutes, 20);
            compare(center.timerSeconds, 2);
            compare(center.timerRemaining, 0);
        }
        function test_timer_completion_once() {
            completion.clear();
            center.timerDeadline = Date.now() - 10;
            center.timerRunning = true;
            center.tick();
            compare(center.timerRemaining, 0);
            verify(center.timerFinished);
            compare(completion.count, 1);
            center.tick();
            compare(completion.count, 1);
        }
        function test_stopwatch_duration() {
            compare(center.duration(3661230, true), "01:01:01.23");
            center.stopwatchElapsed = 5000;
            center.stopwatchStarted = Date.now() - 1000;
            center.stopwatchRunning = true;
            center.tick();
            verify(center.elapsed >= 6000);
            center.stopwatchRunning = false;
        }
    }
}
