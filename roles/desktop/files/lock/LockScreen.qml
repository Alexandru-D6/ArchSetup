pragma ComponentBehavior: Bound
import QtQuick

FocusScope {
    id: screen
    property string profile: ""
    property int clockRevision: 0
    property string status: ""
    property date date: new Date()
    property alias controls: controls
    Timer { interval: 1000; running: true; repeat: true; onTriggered: screen.date = new Date() }
    Rectangle { anchors.fill: parent; color: "#191620" }
    Image {
        anchors.fill: parent
        source: screen.profile ? "file://" + screen.profile + "/assets/lock-wallpaper.jpg" : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    Rectangle { anchors.fill: parent; color: "#26071120" }
    MouseArea { anchors.fill: parent; onClicked: controls.focusPassword() }
    Image {
        anchors.centerIn: parent
        width: Math.min(250, screen.width * 0.4, screen.height * 0.45)
        height: width * 260 / 250
        source: screen.profile ? "file://" + screen.profile + "/theme/lock-clock.png?revision=" + screen.clockRevision : ""
        cache: false
        asynchronous: true
    }
    Text {
        id: lockedLabel
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height / 2 + Math.min(250, screen.width * 0.4, screen.height * 0.45) * 0.52 + 20
        text: "Locked"
        color: "#f0eaff"
        font.family: controls.uiFont
        font.pointSize: controls.fontSize
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: lockedLabel.bottom
        anchors.topMargin: 8
        text: Qt.formatDateTime(screen.date, "dddd, MMMM d")
        color: "#f0eaff"
        font.family: controls.uiFont
        font.pointSize: controls.fontSize
    }
    Text {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 24
        text: screen.status
        textFormat: Text.PlainText
        color: "#f0eaff"
        font.family: controls.uiFont
        font.pointSize: controls.fontSize
    }
    LockControls {
        id: controls
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        height: implicitHeight
        focus: true
    }
}
