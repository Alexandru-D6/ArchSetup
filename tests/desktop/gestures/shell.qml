import QtQuick
import QtQuick.Controls

Window {
    width: 580; height: 600; visible: true
    TimeCenter {
        objectName: "time-center"
        anchors.fill: parent
        tasks: Array.from({length: 40}, (_, index) => ({text: "Task " + index, day: "", done: false}))
        laps: Array(40).fill(12345)
        zones: Array(12).fill("UTC")
        timezoneTimes: ({"UTC": {hour: 12, minute: 30}})
    }
}
