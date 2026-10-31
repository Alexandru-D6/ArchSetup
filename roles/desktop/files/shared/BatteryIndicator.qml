pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

Rectangle {
    id: indicator
    property bool present: false
    property bool charging: false
    property bool pluggedIn: false
    property bool fullyCharged: false
    property real percentage: NaN
    property bool interactive: false
    property string uiFont: "DejaVu Sans"
    property int fontSize: 13
    property color surface: "#35242c"
    property color textColor: "#f9e2e8"
    property color accent: "#ffb1c8"
    property color accentText: "#56122e"
    readonly property bool valid: present && Number.isFinite(percentage) && percentage >= 0 && percentage <= 100
    readonly property bool externalPower: charging || pluggedIn
    readonly property string stateLabel: charging ? "Charging" : pluggedIn ? (fullyCharged || percentage >= 100 ? "Charged" : "Plugged in") : "Battery"
    readonly property string label: (externalPower ? stateLabel + " · " : "") + Math.round(percentage) + "%"
    readonly property color labelColor: externalPower ? accentText : textColor
    signal clicked()
    visible: valid
    implicitWidth: Math.ceil(caption.implicitWidth) + 24 + (externalPower ? 20 : 0)
    implicitHeight: Math.max(30, Math.ceil(caption.implicitHeight) + 12)
    radius: height / 2
    color: externalPower ? accent : surface
    border.width: activeFocus ? 2 : 0
    border.color: labelColor
    activeFocusOnTab: interactive
    Accessible.role: interactive ? Accessible.Button : Accessible.StaticText
    Accessible.name: stateLabel + " " + Math.round(percentage) + "%"
    Accessible.onPressAction: if (interactive) clicked()
    Keys.onReturnPressed: if (interactive) clicked()
    Keys.onSpacePressed: if (interactive) clicked()
    TapHandler { enabled: indicator.interactive; onTapped: indicator.clicked() }
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 6
        Shape {
            objectName: "battery-power-icon"
            visible: indicator.externalPower
            Layout.preferredWidth: 14
            Layout.preferredHeight: 18
            ShapePath {
                fillColor: indicator.labelColor
                strokeWidth: -1
                startX: 8; startY: 0
                PathLine { x: 1; y: 10 }
                PathLine { x: 6; y: 10 }
                PathLine { x: 5; y: 18 }
                PathLine { x: 13; y: 7 }
                PathLine { x: 8; y: 7 }
                PathLine { x: 8; y: 0 }
            }
        }
        Text {
            id: caption
            objectName: "battery-label"
            Layout.fillWidth: true
            text: indicator.label
            textFormat: Text.PlainText
            color: indicator.labelColor
            font.family: indicator.uiFont
            font.pixelSize: indicator.fontSize
            font.weight: indicator.externalPower ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
        }
    }
}
