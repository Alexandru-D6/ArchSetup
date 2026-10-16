pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: center
    property color surface: "#fff8f9"
    property color raised: "#ffe7eb"
    property color textColor: "#3d2c32"
    property color accent: "#bd0056"
    property color accentText: "white"
    property string uiFont: "DejaVu Sans"
    property var tasks: []
    property bool tasksEditable: true
    property string calendarMode: "days"
    property int yearStart: Math.floor(now.getFullYear() / 12) * 12
    property int pickerYear: now.getFullYear()
    property bool showCompleted: false
    property var zones: []
    property var timezoneTimes: ({})
    property string timezoneError: ""
    property bool zonesEditable: true
    readonly property var availableZones: Object.keys(timezoneTimes)
    property int timerHours: 0
    property int timerMinutes: 5
    property int timerSeconds: 0
    property double lastWheelChange: 0
    property int wheelGestureAxis: 0 // 0: undecided, 1: horizontal, 2: vertical
    property real wheelGestureX: 0
    property real wheelGestureY: 0
    property alias currentPage: pageSlider.currentIndex
    onCurrentPageChanged: if (currentPage !== 1) showCompleted = false
    property date now: new Date()
    property date selectedDate: new Date()
    property date month: new Date(now.getFullYear(), now.getMonth(), 1)
    property double timerRemaining: 0
    property double timerDeadline: 0
    property bool timerRunning: false
    property bool timerFinished: false
    property double stopwatchElapsed: 0
    property double stopwatchStarted: 0
    property bool stopwatchRunning: false
    property var laps: []
    readonly property var pages: ["Calendar", "Todo", "Clock", "Timer", "Stopwatch"]
    readonly property string selectedDay: dayKey(selectedDate)
    readonly property double elapsed: stopwatchElapsed + (stopwatchRunning ? now.getTime() - stopwatchStarted : 0)
    signal zonesEdited()
    signal tasksEdited()
    signal closed()
    signal timerCompleted()
    radius: 20
    color: surface
    border.color: raised
    focus: true
    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: center.visible
        onActivated: center.closed()
    }
    Keys.onLeftPressed: switchPage(-1)
    Keys.onRightPressed: switchPage(1)
    function switchPage(delta) { pageSlider.setCurrentIndex((currentPage + delta + pages.length) % pages.length); }
    function wheelPage(delta) {
        if (!delta || Date.now() - lastWheelChange < 300) return;
        lastWheelChange = Date.now(); switchPage(delta < 0 ? 1 : -1);
    }
    function dayKey(date) { return Qt.formatDate(date, "yyyy-MM-dd"); }
    function duration(ms, fractions) {
        const seconds = Math.floor(Math.max(0, ms) / 1000);
        const result = String(Math.floor(seconds / 3600)).padStart(2, "0") + ":" + String(Math.floor(seconds / 60) % 60).padStart(2, "0") + ":" + String(seconds % 60).padStart(2, "0");
        return result + (fractions ? "." + String(Math.floor(ms / 10) % 100).padStart(2, "0") : "");
    }
    function addTask(text, date) {
        if (!tasksEditable || !text.trim()) return;
        tasks = tasks.concat([{text: text.trim(), day: date, done: false}]);
        tasksEdited();
    }
    function changeTask(index, remove) {
        if (!tasksEditable) return;
        let updated = tasks.slice();
        if (remove) updated.splice(index, 1);
        else updated[index] = Object.assign({}, updated[index], {done: !updated[index].done});
        tasks = updated; tasksEdited();
    }
    function goToday() {
        headerClick.stop(); now = new Date(); selectedDate = now;
        month = new Date(now.getFullYear(), now.getMonth(), 1); calendarMode = "days";
    }
    function openYearPicker() {
        pickerYear = month.getFullYear(); yearStart = Math.floor(pickerYear / 12) * 12; calendarMode = "years";
    }
    function pickYear(year) { pickerYear = year; calendarMode = "months"; }
    function pickMonth(index) { month = new Date(pickerYear, index, 1); calendarMode = "days"; }
    function navigateCalendar(delta) {
        if (calendarMode === "years") yearStart += delta * 12;
        else if (calendarMode === "months") pickerYear += delta;
        else moveMonth(delta);
    }
    function addZone(zone) {
        if (!zonesEditable || availableZones.indexOf(zone) < 0 || zones.indexOf(zone) >= 0) return;
        zones = zones.concat([zone]); zonesEdited();
    }
    function removeZone(zone) { if (!zonesEditable) return; zones = zones.filter(value => value !== zone); zonesEdited(); }
    function setTimerPart(part, value) {
        if (timerRunning) return;
        if (timerRemaining > 0) {
            const total = Math.ceil(timerRemaining / 1000);
            timerHours = Math.floor(total / 3600); timerMinutes = Math.floor(total / 60) % 60; timerSeconds = total % 60;
        }
        center[part] = value; timerRemaining = 0; timerFinished = false;
    }
    function todoEntries(done) {
        return tasks.map((task, index) => ({task: task, sourceIndex: index})).filter(entry => entry.task.day === "" && entry.task.done === done);
    }
    function moveMonth(delta) { month = new Date(month.getFullYear(), month.getMonth() + delta, 1); }
    function tick() {
        now = new Date();
        if (timerRunning) {
            timerRemaining = Math.max(0, timerDeadline - now.getTime());
            if (timerRemaining === 0) { timerRunning = false; timerFinished = true; timerCompleted(); }
        }
    }
    Timer { id: headerClick; interval: 300; onTriggered: center.openYearPicker() }
    Timer { interval: center.stopwatchRunning ? 30 : 200; running: true; repeat: true; onTriggered: center.tick() }
    function handlePageWheel(event) {
        const pixels = event.pixelDelta.x !== 0 || event.pixelDelta.y !== 0;
        const dx = pixels ? event.pixelDelta.x : event.angleDelta.x / 8;
        const dy = pixels ? event.pixelDelta.y : event.angleDelta.y / 8;
        if (event.phase === Qt.ScrollBegin) {
            wheelGestureAxis = 0;
            wheelGestureX = 0;
            wheelGestureY = 0;
        }
        const phased = event.phase !== Qt.NoScrollPhase;
        if (phased && wheelGestureAxis === 0) {
            wheelGestureX += dx;
            wheelGestureY += dy;
            // Ignore a few pixels of initial sideways finger jitter.
            if (Math.max(Math.abs(wheelGestureX), Math.abs(wheelGestureY)) >= 8)
                wheelGestureAxis = Math.abs(wheelGestureX) > Math.abs(wheelGestureY) ? 1 : 2;
        }
        const horizontal = phased ? wheelGestureAxis === 1 : Math.abs(dx) > Math.abs(dy);
        event.accepted = horizontal && dx !== 0 && event.phase !== Qt.ScrollEnd;
        if (event.accepted) wheelPage(dx);
        if (event.phase === Qt.ScrollEnd) wheelGestureAxis = 0;
    }
    // The pager's native wheel interaction is disabled below, so neutral begin
    // and end events can reach the vertical lists without stalling page changes.
    MouseArea {
        anchors.fill: parent
        z: 100
        acceptedButtons: Qt.NoButton
        onWheel: event => center.handlePageWheel(event)
    }
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 14
        RowLayout {
            id: navigationRail
            objectName: "time-navigation"
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                model: center.pages
                SettingsButton {
                    required property int index
                    required property string modelData
                    theme: center; text: modelData; primary: center.currentPage === index
                    Layout.fillWidth: true
                    onClicked: pageSlider.setCurrentIndex(index)
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            Text { text: center.pages[center.currentPage]; color: center.textColor; font.family: center.uiFont; font.pixelSize: 24 }
            SwipeView {
                id: pageSlider
                objectName: "time-pages"
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                orientation: Qt.Horizontal
                currentIndex: 0
                // SwipeView's internal Flickable must not also process wheel
                // phases intended for vertical lists. Pointer drags are handled
                // separately, preserving the animated page transition.
                interactive: false
                DragHandler {
                    id: pageDrag
                    property real distance: 0
                    target: null
                    xAxis.enabled: true
                    yAxis.enabled: false
                    onTranslationChanged: if (active) distance = activeTranslation.x
                    onActiveChanged: {
                        if (active) distance = 0;
                        else if (Math.abs(distance) > Math.min(100, pageSlider.width / 4)) center.switchPage(distance < 0 ? 1 : -1);
                    }
                }
                ColumnLayout {
                    RowLayout {
                        SettingsButton { theme: center; text: "‹"; onClicked: center.navigateCalendar(-1) }
                        SettingsButton {
                            objectName: "calendar-heading"
                            theme: center; Layout.fillWidth: true
                            text: center.calendarMode === "years" ? center.yearStart + "–" + (center.yearStart + 11) : center.calendarMode === "months" ? String(center.pickerYear) : Qt.formatDate(center.month, "MMMM yyyy")
                            Accessible.description: "Click to choose year then month; double click for today"
                            onClicked: headerClick.restart()
                            onDoubleClicked: center.goToday()
                        }
                        SettingsButton { theme: center; text: "›"; onClicked: center.navigateCalendar(1) }
                    }
                    GridLayout {
                        visible: center.calendarMode !== "days"
                        columns: 3; Layout.fillWidth: true; Layout.preferredHeight: 220
                        Repeater {
                            model: 12
                            SettingsButton {
                                required property int index
                                theme: center; Layout.fillWidth: true; Layout.fillHeight: true
                                text: center.calendarMode === "years" ? String(center.yearStart + index) : Qt.formatDate(new Date(center.pickerYear, index, 1), "MMM")
                                primary: center.calendarMode === "years" ? center.yearStart + index === center.month.getFullYear() : index === center.month.getMonth() && center.pickerYear === center.month.getFullYear()
                                onClicked: center.calendarMode === "years" ? center.pickYear(center.yearStart + index) : center.pickMonth(index)
                            }
                        }
                    }
                    GridLayout {
                        visible: center.calendarMode === "days"
                        columns: 7; uniformCellWidths: true; Layout.fillWidth: true; rowSpacing: 2; columnSpacing: 2
                        Repeater {
                            model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                            Text { required property string modelData; text: modelData; color: center.textColor; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 11 }
                        }
                        Repeater {
                            model: 42
                            Button {
                                id: day
                                required property int index
                                readonly property date date: new Date(center.month.getFullYear(), center.month.getMonth(), index - ((center.month.getDay() + 6) % 7) + 1)
                                readonly property string key: center.dayKey(date)
                                objectName: "calendar-day-" + index
                                Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: 0
                                implicitWidth: 1; implicitHeight: 30; padding: 0
                                text: String(date.getDate())
                                opacity: date.getMonth() === center.month.getMonth() ? 1 : 0.4
                                background: Rectangle { radius: 10; color: day.key === center.selectedDay ? center.accent : center.raised; border.width: day.key === center.dayKey(center.now) ? 1 : 0; border.color: center.accent }
                                contentItem: Item {
                                    Text { objectName: "day-number"; anchors.centerIn: parent; text: day.text; color: day.key === center.selectedDay ? center.accentText : center.textColor }
                                    Rectangle {
                                        objectName: "task-dot"
                                        visible: center.tasks.some(task => task.day === day.key && !task.done)
                                        width: 3; height: 3; radius: 1.5
                                        x: parent.width / 2 + 15; anchors.verticalCenter: parent.verticalCenter
                                        color: day.key === center.selectedDay ? center.accentText : center.textColor
                                    }
                                }
                                onClicked: center.selectedDate = date
                                Accessible.name: Qt.formatDate(date, "dddd d MMMM yyyy")
                            }
                        }
                    }
                    Text { text: Qt.formatDate(center.selectedDate, "dddd, d MMMM"); color: center.textColor }
                    TaskList { dayFilter: center.selectedDay; Layout.fillWidth: true; Layout.fillHeight: true }
                    RowLayout {
                        TextField { id: dailyInput; Layout.fillWidth: true; placeholderText: "Task for this day"; onAccepted: dailyAdd.clicked() }
                        SettingsButton { id: dailyAdd; theme: center; text: "Add"; onClicked: { center.addTask(dailyInput.text, center.selectedDay); dailyInput.clear(); } }
                    }
                }
                ColumnLayout {
                    RowLayout {
                        Text { text: center.showCompleted ? "Completed tasks" : "Pending tasks"; color: center.textColor; Layout.fillWidth: true }
                        SettingsButton { theme: center; text: center.showCompleted ? "Back to pending" : "Completed (" + center.todoEntries(true).length + ")"; onClicked: center.showCompleted = !center.showCompleted }
                    }
                    TaskList { objectName: "todo-list"; dayFilter: ""; completionFilter: center.showCompleted ? 1 : 0; Layout.fillWidth: true; Layout.fillHeight: true }
                    RowLayout {
                        visible: !center.showCompleted
                        TextField { id: todoInput; Layout.fillWidth: true; placeholderText: "New todo"; onAccepted: todoAdd.clicked() }
                        SettingsButton { id: todoAdd; theme: center; text: "Add"; onClicked: { center.addTask(todoInput.text, ""); todoInput.clear(); } }
                    }
                }
                ScrollView {
                    id: clockScroll
                    objectName: "world-clock-scroll"
                    clip: true
                    contentWidth: availableWidth
                    ColumnLayout {
                        width: clockScroll.availableWidth; spacing: 12
                        RowLayout {
                            Layout.fillWidth: true; spacing: 12
                            ClockReadout { label: "Machine time"; utc: false; Layout.fillWidth: true }
                            ClockReadout { label: "UTC+0"; utc: true; Layout.fillWidth: true }
                        }
                        TextEdit { text: "Unix seconds: " + Math.floor(center.now.getTime() / 1000); readOnly: true; selectByMouse: true; color: center.textColor; Layout.fillWidth: true; horizontalAlignment: TextEdit.AlignHCenter }
                        TimezoneSearch { Layout.fillWidth: true }
                        Text { visible: center.availableZones.length === 0; text: center.timezoneError || "Loading timezones…"; color: center.textColor }
                        GridLayout {
                            Layout.fillWidth: true; columns: 2
                            Repeater {
                                model: center.zones
                                ColumnLayout {
                                    id: zoneCard
                                    required property string modelData
                                    readonly property var time: center.timezoneTimes[modelData] || ({hour: 0, minute: 0})
                                    Layout.fillWidth: true
                                    Item {
                                        Layout.alignment: Qt.AlignHCenter
                                        implicitWidth: 130; implicitHeight: 130
                                        Rectangle { anchors.fill: parent; radius: width / 2; color: center.raised; border.color: center.accent }
                                        Repeater {
                                            model: 12
                                            Item {
                                                required property int index
                                                anchors.fill: parent; rotation: index * 30
                                                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 6; width: 2; height: 7; color: center.textColor }
                                            }
                                        }
                                        Item {
                                            anchors.fill: parent; rotation: (zoneCard.time.hour % 12 + zoneCard.time.minute / 60) * 30
                                            Rectangle { width: 4; height: 33; radius: 2; anchors.horizontalCenter: parent.horizontalCenter; y: 32; color: center.textColor }
                                        }
                                        Item {
                                            anchors.fill: parent; rotation: zoneCard.time.minute * 6
                                            Rectangle { width: 3; height: 48; radius: 2; anchors.horizontalCenter: parent.horizontalCenter; y: 17; color: center.accent }
                                        }
                                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: center.accent }
                                        Accessible.role: Accessible.Clock
                                        Accessible.name: zoneCard.modelData + " " + zoneCard.time.hour + ":" + String(zoneCard.time.minute).padStart(2, "0")
                                    }
                                    Text { text: zoneCard.modelData; color: center.textColor; font.pixelSize: 11; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap }
                                    SettingsButton { theme: center; text: "Remove"; Layout.alignment: Qt.AlignHCenter; onClicked: center.removeZone(zoneCard.modelData) }
                                }
                            }
                        }
                        SettingsButton { id: conversionsButton; theme: center; text: checked ? "Hide conversions" : "More conversions"; checkable: true }
                        ColumnLayout {
                            visible: conversionsButton.checked; Layout.fillWidth: true
                            TextEdit { text: "Unix milliseconds: " + center.now.getTime(); readOnly: true; selectByMouse: true; color: center.textColor }
                            TextField { id: timestampInput; Layout.fillWidth: true; placeholderText: "Convert Unix seconds to date" }
                            TextEdit {
                                Layout.fillWidth: true; readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; color: center.textColor
                                text: { const value = Number(timestampInput.text); const date = new Date(value * 1000); return !timestampInput.text.trim() ? "" : isFinite(value) && !isNaN(date.getTime()) ? date.toISOString() + "\n" + date.toString() : "Enter a valid Unix timestamp"; }
                            }
                        }
                    }
                }
                ColumnLayout {
                    Layout.maximumWidth: Infinity
                    Item { Layout.fillHeight: true }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: false; Layout.preferredWidth: 350; Layout.maximumWidth: 350; spacing: 2
                        TimerNumber { objectName: "timer-hours"; label: "Hours"; value: center.timerHours; maximum: 99; displayed: Math.floor(Math.ceil(center.timerRemaining / 1000) / 3600); onEdited: value => center.setTimerPart("timerHours", value) }
                        Text { text: ":"; font.pixelSize: 46; color: center.accent }
                        TimerNumber { objectName: "timer-minutes"; label: "Minutes"; value: center.timerMinutes; maximum: 59; displayed: Math.floor(Math.ceil(center.timerRemaining / 1000) / 60) % 60; onEdited: value => center.setTimerPart("timerMinutes", value) }
                        Text { text: ":"; font.pixelSize: 46; color: center.accent }
                        TimerNumber { objectName: "timer-seconds"; label: "Seconds"; value: center.timerSeconds; maximum: 59; displayed: Math.ceil(center.timerRemaining / 1000) % 60; onEdited: value => center.setTimerPart("timerSeconds", value) }
                    }
                    Text { text: "Time is up!"; visible: center.timerFinished; color: center.textColor; Layout.alignment: Qt.AlignHCenter }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        SettingsButton {
                            theme: center; text: center.timerRunning ? "Pause" : center.timerRemaining > 0 ? "Resume" : "Start"; primary: true
                            onClicked: {
                                center.tick();
                                if (center.timerRunning) center.timerRunning = false;
                                else {
                                    if (center.timerRemaining <= 0) center.timerRemaining = (center.timerHours * 3600 + center.timerMinutes * 60 + center.timerSeconds) * 1000;
                                    center.timerFinished = false;
                                    center.timerDeadline = Date.now() + center.timerRemaining;
                                    center.timerRunning = center.timerRemaining > 0;
                                }
                            }
                        }
                        SettingsButton { theme: center; text: "Reset"; onClicked: { center.timerRunning = false; center.timerRemaining = 0; center.timerFinished = false; } }
                    }
                    Item { Layout.fillHeight: true }
                }
                Item {
                    ColumnLayout {
                        id: stopwatchControls
                        anchors.centerIn: parent
                        width: parent.width
                        Text { objectName: "stopwatch-display"; text: center.duration(center.elapsed, true); font.pixelSize: 48; fontSizeMode: Text.Fit; minimumPixelSize: 24; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; color: center.accent }
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            SettingsButton {
                                theme: center; text: center.stopwatchRunning ? "Pause" : "Start"; primary: true
                                onClicked: {
                                    center.now = new Date();
                                    if (center.stopwatchRunning) center.stopwatchElapsed = center.elapsed;
                                    else center.stopwatchStarted = Date.now();
                                    center.stopwatchRunning = !center.stopwatchRunning;
                                }
                            }
                            SettingsButton { theme: center; text: "Lap"; enabled: center.stopwatchRunning; onClicked: center.laps = [center.elapsed].concat(center.laps) }
                            SettingsButton { theme: center; text: "Reset"; onClicked: { center.stopwatchRunning = false; center.stopwatchElapsed = 0; center.laps = []; } }
                        }
                    }
                    ListView {
                        objectName: "stopwatch-laps"
                        anchors { top: stopwatchControls.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; topMargin: 24 }
                        clip: true; model: center.laps
                        ScrollBar.vertical: ScrollBar {}
                        delegate: Text { required property int index; required property double modelData; text: "Lap " + (center.laps.length - index) + "     " + center.duration(modelData, true); color: center.textColor; height: 32 }
                    }
                }
            }
        }
    }
    component ClockReadout: ColumnLayout {
        required property string label
        required property bool utc
        Text { text: parent.label; color: center.textColor; Layout.alignment: Qt.AlignHCenter }
        Text {
            objectName: parent.utc ? "utc-clock-time" : "machine-clock-time"
            text: parent.utc ? center.now.toISOString().slice(11, 19) : Qt.formatTime(center.now, "HH:mm:ss")
            color: center.accent; font.family: center.uiFont; font.pixelSize: 32
            fontSizeMode: Text.Fit; minimumPixelSize: 18
            Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
        }
        Text {
            text: Qt.formatDate(parent.utc ? new Date(center.now.getUTCFullYear(), center.now.getUTCMonth(), center.now.getUTCDate()) : center.now, "dddd, d MMMM yyyy")
            color: center.textColor; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
        }
    }
    component TimezoneSearch: RowLayout {
        id: search
        objectName: "timezone-search"
        readonly property var matches: {
            const terms = input.text.trim().toLowerCase().replace(/_/g, " ").split(/\s+/).filter(Boolean);
            return center.availableZones.filter(zone => center.zones.indexOf(zone) < 0 && terms.every(term => zone.toLowerCase().replace(/_/g, " ").includes(term)));
        }
        onMatchesChanged: results.currentIndex = matches.length ? 0 : -1
        function choose(zone) {
            if (!center.zonesEditable || matches.indexOf(zone) < 0) return;
            center.addZone(zone);
            input.clear();
            input.forceActiveFocus();
        }
        function submit() {
            if (!input.text.trim() || !matches.length) return;
            const exact = matches.find(zone => zone.toLowerCase() === input.text.trim().toLowerCase());
            choose(exact || matches[Math.max(0, results.currentIndex)]);
        }
        function moveSelection(delta) {
            results.currentIndex = Math.max(0, Math.min(matches.length - 1, results.currentIndex + delta));
            results.positionViewAtIndex(results.currentIndex, ListView.Contain);
        }
        TextField {
            id: input
            objectName: "timezone-search-input"
            Layout.fillWidth: true
            implicitHeight: 40
            enabled: center.zonesEditable
            placeholderText: "Search timezones (e.g. Madrid)"
            color: center.textColor
            placeholderTextColor: center.textColor
            selectionColor: center.accent; selectedTextColor: center.accentText
            font.family: center.uiFont; font.pixelSize: 13
            leftPadding: 12; rightPadding: 12
            selectByMouse: true
            background: Rectangle {
                radius: 12; color: center.surface
                border.width: input.activeFocus ? 2 : 1
                border.color: input.activeFocus ? center.accent : center.raised
            }
            Accessible.name: "Search timezones"
            onAccepted: search.submit()
            Keys.onDownPressed: search.moveSelection(1)
            Keys.onUpPressed: search.moveSelection(-1)
            Popup {
                id: suggestions
                objectName: "timezone-search-popup"
                y: input.height + 4
                width: input.width
                height: Math.min(216, Math.max(1, results.count) * 36) + padding * 2
                padding: 6
                popupType: Popup.Item
                focus: false
                modal: false
                dim: false
                closePolicy: Popup.CloseOnPressOutsideParent
                visible: center.visible && center.currentPage === 2 && input.activeFocus && input.text.trim().length > 0
                background: Rectangle {
                    radius: 12; color: center.surface
                    border.color: center.raised
                }
                contentItem: Item {
                    ListView {
                        id: results
                        objectName: "timezone-search-results"
                        anchors.fill: parent
                        visible: count > 0
                        clip: true
                        model: search.matches
                        highlightMoveDuration: 0
                        ScrollBar.vertical: ScrollBar {}
                        delegate: ItemDelegate {
                            id: result
                            required property string modelData
                            required property int index
                            width: results.width; height: 36
                            // Selecting a suggestion must not take typing focus
                            // and dismiss the popup before the click completes.
                            focusPolicy: Qt.NoFocus
                            text: modelData
                            highlighted: results.currentIndex === index
                            contentItem: Text { text: result.text; color: result.highlighted ? center.accentText : center.textColor; font.family: center.uiFont; font.pixelSize: 13; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter }
                            background: Rectangle { radius: 10; color: result.highlighted ? center.accent : result.hovered ? center.raised : center.surface }
                            onClicked: search.choose(modelData)
                        }
                    }
                    Text {
                        objectName: "timezone-search-empty"
                        anchors.fill: parent; anchors.leftMargin: 6
                        visible: results.count === 0
                        text: "No matching timezones"
                        color: center.textColor; font.family: center.uiFont; font.pixelSize: 12
                        verticalAlignment: Text.AlignVCenter
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        onWheel: event => center.handlePageWheel(event)
                    }
                }
            }
        }
        SettingsButton {
            objectName: "timezone-search-add"
            theme: center; text: "Add"
            enabled: center.zonesEditable && input.text.trim().length > 0 && search.matches.length > 0
            onClicked: search.submit()
        }
    }
    component TimerArrow: Button {
        id: arrow
        implicitHeight: 34
        hoverEnabled: enabled
        opacity: enabled ? (hovered || visualFocus ? 1 : 0.55) : 0.25
        contentItem: Text { text: arrow.text; color: center.textColor; font.pixelSize: 30; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        background: Rectangle { radius: 12; color: arrow.enabled && (arrow.hovered || arrow.visualFocus) ? center.raised : "transparent" }
    }
    component TimerNumber: ColumnLayout {
        id: number
        required property string label
        required property int value
        required property int maximum
        required property int displayed
        readonly property int currentValue: center.timerRemaining > 0 ? displayed : value
        property real wheelRemainder: 0
        signal edited(int value)
        function adjust(steps) {
            if (center.timerRunning) return;
            edited(Math.max(0, Math.min(maximum, currentValue + steps)));
            numberInput.text = Qt.binding(() => String(number.currentValue).padStart(2, "0"));
        }
        spacing: 4
        Layout.preferredWidth: 94; Layout.maximumWidth: 104
        TimerArrow { objectName: "increase"; text: "▴"; Layout.fillWidth: true; enabled: !center.timerRunning; Accessible.name: "Increase " + number.label; onClicked: number.adjust(1) }
        TextField {
            id: numberInput
            objectName: "timer-number-input"
            Layout.preferredWidth: 80; Layout.maximumWidth: 80; Layout.alignment: Qt.AlignHCenter
            text: String(number.currentValue).padStart(2, "0")
            font.pixelSize: 42; horizontalAlignment: TextInput.AlignHCenter; color: center.accent
            readOnly: center.timerRunning
            hoverEnabled: !readOnly
            validator: IntValidator { bottom: 0; top: number.maximum }
            selectByMouse: true
            Accessible.name: number.label
            onActiveFocusChanged: if (activeFocus) selectAll()
            onTextEdited: if (acceptableInput) number.edited(Number(text))
            onEditingFinished: { text = Qt.binding(() => String(number.currentValue).padStart(2, "0")); }
            MouseArea {
                anchors.fill: parent
                z: 1
                acceptedButtons: Qt.NoButton
                onWheel: event => {
                    const pixels = event.pixelDelta.x !== 0 || event.pixelDelta.y !== 0;
                    const dx = pixels ? event.pixelDelta.x : event.angleDelta.x;
                    const dy = pixels ? event.pixelDelta.y : event.angleDelta.y;
                    event.accepted = Math.abs(dy) >= Math.abs(dx);
                    if (!event.accepted) return;
                    if (event.phase === Qt.ScrollBegin || event.phase === Qt.ScrollEnd || center.timerRunning)
                        number.wheelRemainder = 0;
                    if (center.timerRunning || !dy) return;
                    const delta = pixels ? dy / 24 : dy / 120;
                    if (number.wheelRemainder * delta < 0) number.wheelRemainder = 0;
                    number.wheelRemainder += delta;
                    const steps = Math.trunc(number.wheelRemainder);
                    if (steps) { number.wheelRemainder -= steps; number.adjust(steps); }
                }
            }
        }
        TimerArrow { objectName: "decrease"; text: "▾"; Layout.fillWidth: true; enabled: !center.timerRunning; Accessible.name: "Decrease " + number.label; onClicked: number.adjust(-1) }
        Text { text: number.label; color: center.textColor; font.pixelSize: 11; Layout.alignment: Qt.AlignHCenter }

    }
    component TaskList: ListView {
        id: list
        required property string dayFilter
        property int completionFilter: -1
        clip: true; spacing: 4
        model: center.tasks.map((task, index) => ({task: task, sourceIndex: index})).filter(entry => entry.task.day === dayFilter && (completionFilter < 0 || entry.task.done === (completionFilter === 1)))
        ScrollBar.vertical: ScrollBar {}
        Text { visible: list.count === 0; text: "No tasks yet"; color: center.textColor }
        delegate: RowLayout {
            id: taskRow
            required property var modelData
            width: list.width
            CheckBox { checked: taskRow.modelData.task.done; onClicked: center.changeTask(taskRow.modelData.sourceIndex, false); Accessible.name: taskRow.modelData.task.text }
            Text { text: taskRow.modelData.task.text; textFormat: Text.PlainText; font.strikeout: taskRow.modelData.task.done; color: center.textColor; wrapMode: Text.Wrap; Layout.fillWidth: true }
            SettingsButton { theme: center; text: "×"; Accessible.name: "Delete task"; onClicked: center.changeTask(taskRow.modelData.sourceIndex, true) }
        }
    }
}
