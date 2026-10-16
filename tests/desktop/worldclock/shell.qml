import QtQuick
import Quickshell

ShellRoot {
    WorldClockSource {
        id: clocks
        active: false
        onTimesChanged: {
            if (!times.UTC || !times["Asia/Kathmandu"] || !times["Europe/Madrid"]) return;
            const date = new Date();
            if (times.UTC.hour !== date.getUTCHours() || times.UTC.minute !== date.getUTCMinutes()) throw new Error("UTC mismatch");
            const nepal = new Date(date.getTime() + 345 * 60000);
            if (times["Asia/Kathmandu"].hour !== nepal.getUTCHours() || times["Asia/Kathmandu"].minute !== nepal.getUTCMinutes()) throw new Error("Fractional timezone mismatch");
            console.log("ARCHSETUP_WORLD_CLOCKS_PASSED");
            Qt.quit();
        }
    }
    Timer { interval: 5000; running: true; onTriggered: { console.error("World clocks did not load: " + clocks.error); Qt.exit(1); } }
}
