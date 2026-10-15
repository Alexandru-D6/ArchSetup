pragma ComponentBehavior: Bound
import QtQuick
import "shared"

FocusScope {
    id: screen
    property string profile: ""
    property int clockRevision: 0
    property string status: ""
    property date date: new Date()
    property string dateCaption: ""
    property var clockPosition: null
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
    PlacedClock {
        id: clockGroup
        objectName: "lock-clock-group"
        position: screen.clockPosition
        safeTop: 64
        safeBottom: Math.max(140, controls.height + 44)
        readonly property real dialSize: Math.max(1, Math.min(250, screen.width * 0.4, screen.height * 0.45,
            (screen.height - safeTop - safeBottom - captions.height - 20) * 250 / 260))
        readonly property real dialHeight: dialSize * 260 / 250
        visible: screen.height - safeTop - safeBottom > captions.height + 24
        width: Math.min(screen.width - 32, Math.max(300, dialSize))
        height: dialHeight + 20 + captions.height
        defaultX: (screen.width - width) / 2
        defaultY: (screen.height - dialHeight) / 2
        Image {
            objectName: "lock-clock"
            anchors.horizontalCenter: parent.horizontalCenter
            width: clockGroup.dialSize
            height: clockGroup.dialHeight
            source: screen.profile ? "file://" + screen.profile + "/theme/lock-clock.png?revision=" + screen.clockRevision : ""
            cache: false
            asynchronous: true
            retainWhileLoading: true
        }
        Column {
            id: captions
            y: clockGroup.dialHeight + 20
            width: parent.width
            spacing: 8
            Text {
                width: parent.width
                text: "Locked"
                color: "#f0eaff"
                font.family: controls.uiFont
                font.pointSize: controls.fontSize
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
            Text {
                objectName: "lock-clock-date"
                width: parent.width
                text: screen.dateCaption || Qt.formatDateTime(screen.date, "dddd, MMMM d")
                color: "#f0eaff"
                font.family: controls.uiFont
                font.pointSize: controls.fontSize
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }
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
