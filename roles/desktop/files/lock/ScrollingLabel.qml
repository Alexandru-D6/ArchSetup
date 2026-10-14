pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: label
    property string text: ""
    property string uiFont: "DejaVu Sans"
    property int fontSize: 12
    property color color: "#eae0f5"
    property bool reducedMotion: false
    property string currentText: ""
    property string previousText: ""
    property real progress: 1
    property bool ready: false
    readonly property bool animating: scroll.running
    implicitWidth: Math.ceil(Math.max(current.implicitWidth, animating ? previous.implicitWidth : 0))
    implicitHeight: Math.ceil(metrics.height)
    clip: true

    FontMetrics { id: metrics; font: current.font }
    onTextChanged: {
        scroll.stop();
        previousText = currentText;
        currentText = text;
        if (ready && !reducedMotion && previousText !== currentText) scroll.restart();
        else progress = 1;
    }
    onReducedMotionChanged: if (reducedMotion) { scroll.stop(); progress = 1; }
    Component.onCompleted: { currentText = text; ready = true; }
    NumberAnimation {
        id: scroll
        target: label
        property: "progress"
        from: 0
        to: 1
        duration: 180
        easing.type: Easing.OutCubic
    }
    Text {
        id: previous
        width: parent.width
        y: -label.progress * label.height
        text: label.previousText
        textFormat: Text.PlainText
        color: label.color
        font: current.font
        elide: Text.ElideRight
    }
    Text {
        id: current
        width: parent.width
        y: (1 - label.progress) * label.height
        text: label.currentText
        textFormat: Text.PlainText
        color: label.color
        font.family: label.uiFont
        font.pointSize: label.fontSize
        elide: Text.ElideRight
    }
}
