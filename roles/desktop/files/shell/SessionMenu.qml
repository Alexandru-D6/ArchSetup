pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FocusScope {
    id: menu
    property string uiFont: "DejaVu Sans"
    property int fontSize: 12
    property color textColor: "#e6e1e1"
    property bool light: false
    property bool reducedMotion: false
    property bool canFirmwareSetup: false
    property int selectedIndex: 0
    property bool committed: false
    property point pointerPosition: Qt.point(-1, -1)
    readonly property string selectedAction: choices[selectedIndex].action
    readonly property real tileSize: Math.max(40, Math.min(96, (width - 84) / 4, (height - 160) / 2))
    readonly property color tileColor: light ? "#dce5ff" : "#304779"
    readonly property color selectionColor: light ? "#385995" : "#afc2ff"
    readonly property var choices: [
        {action: "lock", label: "Lock", enabled: true},
        {action: "suspend", label: "Suspend", enabled: true},
        {action: "logout", label: "Log out", enabled: true},
        {action: "task-manager", label: "Task manager", enabled: true},
        {action: "settings", label: "Settings", enabled: true},
        {action: "poweroff", label: "Shut down", enabled: true},
        {action: "reboot", label: "Restart", enabled: true},
        {action: "firmware-setup", label: "Restart to BIOS / UEFI", enabled: canFirmwareSetup}
    ]
    signal activated(string action)
    signal cancelled()

    function select(action) {
        const index = choices.findIndex(choice => choice.action === action && choice.enabled);
        selectedIndex = index >= 0 ? index : 0;
        committed = false;
    }
    function move(delta) {
        let index = selectedIndex;
        for (let count = 0; count < choices.length; count++) {
            index = (index + delta + choices.length) % choices.length;
            if (choices[index].enabled) { selectedIndex = index; return; }
        }
    }
    function activate(index) {
        if (!visible || committed || !choices[index].enabled) return;
        selectedIndex = index;
        committed = true;
        activated(choices[index].action);
    }
    function cancel() {
        if (!visible || committed) return;
        committed = true;
        cancelled();
    }
    function hoverAt(position) {
        // Showing the overlay generates hover events under a stationary pointer.
        // Keep the requested action until the pointer actually moves.
        if (pointerPosition.x >= 0 && !committed &&
                (position.x !== pointerPosition.x || position.y !== pointerPosition.y)) {
            for (let index = 0; index < tiles.count; index++) {
                const tile = tiles.itemAt(index);
                if (tile.enabled && tile.contains(tile.mapFromItem(menu, position.x, position.y))) {
                    selectedIndex = index;
                    break;
                }
            }
        }
        pointerPosition = position;
    }
    onCanFirmwareSetupChanged: if (!canFirmwareSetup && selectedAction === "firmware-setup") selectedIndex = 0
    onVisibleChanged: if (visible) {
        committed = false;
        pointerPosition = Qt.point(-1, -1);
        forceActiveFocus();
    }

    HoverHandler {
        onPointChanged: if (menu.visible) menu.hoverAt(point.position)
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Left) move(-1);
        else if (event.key === Qt.Key_Right) move(1);
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) move(4);
        else if (event.key === Qt.Key_Tab) move(event.modifiers & Qt.ShiftModifier ? -1 : 1);
        else if (event.key === Qt.Key_Backtab) move(-1);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            if (!event.isAutoRepeat) activate(selectedIndex);
        } else if (event.key === Qt.Key_Escape) cancel();
        else return;
        event.accepted = true;
    }

    MouseArea {
        anchors.fill: parent
        onClicked: menu.cancel()
    }
    ColumnLayout {
        anchors.centerIn: parent
        spacing: 12
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 2
            Text {
                text: "Session"
                color: menu.textColor
                font.family: menu.uiFont
                font.pointSize: menu.fontSize
                font.weight: Font.Medium
                Layout.alignment: Qt.AlignHCenter
            }
            Text {
                text: "Arrow keys to navigate, Enter to select\nEsc or click the background to cancel"
                color: menu.textColor
                font.family: menu.uiFont
                font.pointSize: menu.fontSize
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }
        }
        GridLayout {
            columns: 4
            rowSpacing: 12
            columnSpacing: 12
            Layout.alignment: Qt.AlignHCenter
            Repeater {
                id: tiles
                model: menu.choices
                Button {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property bool selected: menu.selectedIndex === index
                    objectName: "session-" + modelData.action
                    Layout.preferredWidth: menu.tileSize
                    Layout.preferredHeight: menu.tileSize
                    padding: 0
                    enabled: modelData.enabled
                    opacity: enabled ? 1 : 0.35
                    focusPolicy: Qt.NoFocus
                    hoverEnabled: true
                    Accessible.name: modelData.label
                    Accessible.description: modelData.action === "firmware-setup" && !enabled ? "BIOS / UEFI access is unavailable on this machine" : ""
                    onClicked: menu.activate(index)
                    background: Rectangle {
                        color: tile.selected ? menu.selectionColor : menu.tileColor
                        radius: tile.selected ? width / 2 : width / 4
                        Behavior on radius { NumberAnimation { duration: menu.reducedMotion ? 0 : 120 } }
                    }
                    contentItem: Item {
                        SessionIcon {
                            objectName: "session-icon"
                            anchors.centerIn: parent
                            width: Math.min(36, menu.tileSize * 0.45)
                            height: width
                            name: tile.modelData.action
                            color: tile.selected ? (menu.light ? "#ffffff" : "#123367") : menu.textColor
                        }
                    }
                    ToolTip {
                        visible: tile.hovered && !tile.enabled
                        text: "BIOS / UEFI access is unavailable on this machine"
                        font.family: menu.uiFont
                        font.pointSize: menu.fontSize
                    }
                }
            }
        }
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: selectionLabel.implicitWidth + 28
            implicitHeight: 32
            radius: height / 2
            color: menu.light ? "#e4d8e7" : "#ecdfee"
            Text {
                id: selectionLabel
                anchors.centerIn: parent
                text: menu.choices[menu.selectedIndex].label
                color: "#3a303e"
                font.family: menu.uiFont
                font.pointSize: menu.fontSize
            }
        }
    }
}
