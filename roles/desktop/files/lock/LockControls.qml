pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

FocusScope {
    id: controls
    property string username: ""
    property string layout: "US"
    property string uiFont: "DejaVu Sans"
    property int fontSize: 12
    property bool reducedMotion: false
    property bool busy: false
    property bool capsLock: false
    property bool powerActionsEnabled: false
    property string prompt: "Enter password"
    property string message: ""
    property string poweroffLabel: "Power off"
    property string rebootLabel: "Reboot"
    property color surface: "#292332"
    property color ink: "#eae0f5"
    property color outline: "#45404f"
    readonly property real maximumPillWidth: Math.max(1, width - 32)
    readonly property real pillHeight: Math.max(50, Math.ceil(labelMetrics.height) + 20)
    implicitHeight: toolbar.height + (notice.visible ? notice.implicitHeight + 12 : 0)
    signal submitted(string response)
    signal powerPressed(string action)
    signal capsLockToggled()

    function focusPassword() { input.forceActiveFocus(); }
    function clearPassword() { input.clear(); }
    function submit() {
        if (busy) return;
        submitted(input.text);
        input.clear();
        input.forceActiveFocus();
    }
    Component.onCompleted: focusPassword()
    onBusyChanged: if (!busy) focusPassword()

    FontMetrics {
        id: labelMetrics
        font.family: controls.uiFont
        font.pointSize: controls.fontSize
    }
    Text {
        id: notice
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: toolbar.top
        anchors.bottomMargin: 12
        width: controls.maximumPillWidth
        text: [controls.message, controls.capsLock ? "Caps Lock is on" : ""].filter(Boolean).join(" · ")
        textFormat: Text.PlainText
        visible: text.length > 0
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        color: "#f0eaff"
        font.family: controls.uiFont
        font.pointSize: controls.fontSize
    }
    Flow {
        id: toolbar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: Math.min(controls.maximumPillWidth, identity.width + password.width + spacing
                        + (controls.powerActionsEnabled ? poweroff.width + reboot.width + spacing * 2 : 0))
        height: implicitHeight
        spacing: 12

        Rectangle {
            id: identity
            objectName: "lock-identity"
            width: identityRow.width + 32
            height: Math.max(50, identityRow.height + 20)
            radius: height / 2
            color: controls.surface
            border.color: controls.outline
            border.width: 1
            Row {
                id: identityRow
                anchors.centerIn: parent
                spacing: 8
                Text {
                    id: userLabel
                    objectName: "lock-username"
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, Math.max(0, controls.maximumPillWidth - layoutLabel.width - separator.width - 48))
                    text: controls.username
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: controls.ink
                    font.family: controls.uiFont
                    font.pointSize: controls.fontSize
                }
                Text {
                    id: separator
                    anchors.verticalCenter: parent.verticalCenter
                    text: "·"
                    color: controls.ink
                    font: userLabel.font
                }
                ScrollingLabel {
                    id: layoutLabel
                    objectName: "lock-layout"
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, Math.max(0, controls.maximumPillWidth * 0.6 - 32))
                    height: implicitHeight
                    text: controls.layout
                    uiFont: controls.uiFont
                    fontSize: controls.fontSize
                    color: controls.ink
                    reducedMotion: controls.reducedMotion
                }
            }
        }
        Rectangle {
            id: password
            objectName: "lock-password-pill"
            width: Math.min(controls.maximumPillWidth, controls.width * 0.15)
            height: controls.pillHeight
            radius: height / 2
            color: controls.surface
            border.color: controls.outline
            border.width: 1
            Item {
                id: inputArea
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                height: Math.max(mask.height, placeholder.implicitHeight)
                clip: true
                TextInput {
                    id: input
                    objectName: "lock-password"
                    anchors.fill: parent
                    enabled: !controls.busy
                    focus: true
                    color: "transparent"
                    selectionColor: "transparent"
                    selectedTextColor: "transparent"
                    cursorVisible: false
                    echoMode: TextInput.Password
                    passwordMaskDelay: 0
                    inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                    font.family: controls.uiFont
                    font.pointSize: controls.fontSize
                    onAccepted: controls.submit()
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) { clear(); event.accepted = true; }
                        else if (event.key === Qt.Key_CapsLock && !event.isAutoRepeat) controls.capsLockToggled();
                    }
                }
                Text {
                    id: placeholder
                    anchors.fill: parent
                    visible: input.length === 0
                    text: controls.busy ? "Checking…" : controls.prompt
                    textFormat: Text.PlainText
                    color: controls.ink
                    font: input.font
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
                PasswordShapes {
                    id: mask
                    objectName: "lock-password-shapes"
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.min(0, inputArea.width - input.cursorPosition * (shapeSize + spacing) - 4)
                    height: implicitHeight
                    count: input.length
                    color: controls.ink
                }
                Rectangle {
                    visible: input.activeFocus && !controls.busy && input.length > 0
                    x: Math.min(inputArea.width - 1, mask.x + input.cursorPosition * (mask.shapeSize + mask.spacing))
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: inputArea.height
                    color: controls.ink
                }
            }
        }
        component PowerButton: Button {
            id: button
            visible: controls.powerActionsEnabled
            enabled: controls.powerActionsEnabled
            property string powerAction: ""
            property real pillWidth: 136
            width: Math.min(controls.maximumPillWidth, implicitWidth)
            implicitWidth: pillWidth
            implicitHeight: controls.pillHeight
            leftPadding: 16
            rightPadding: 16
            topPadding: 10
            bottomPadding: 10
            focusPolicy: Qt.NoFocus
            onClicked: {
                if (controls.powerActionsEnabled) controls.powerPressed(powerAction);
                controls.focusPassword();
            }
            background: Rectangle {
                radius: height / 2
                color: controls.surface
                border.width: 1
                border.color: controls.outline
            }
            contentItem: Text {
                objectName: "lock-power-caption"
                text: button.text
                textFormat: Text.PlainText
                font.family: controls.uiFont
                font.pointSize: controls.fontSize
                color: controls.ink
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
        PowerButton { id: poweroff; objectName: "lock-poweroff"; powerAction: "poweroff"; text: controls.poweroffLabel }
        PowerButton { id: reboot; objectName: "lock-reboot"; powerAction: "reboot"; pillWidth: 120; text: controls.rebootLabel }
    }
}
