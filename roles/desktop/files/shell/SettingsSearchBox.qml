pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

Item {
    id: control
    required property var theme
    property var options: []
    property alias text: input.text
    property alias placeholderText: input.placeholderText
    property string accessibleName: "Search options"
    property string query: ""
    readonly property var selectedOption: options.find(option => option.name.toLowerCase() === text.trim().toLowerCase()
        || option.id.toLowerCase() === text.trim().toLowerCase()) || null
    readonly property bool valid: selectedOption !== null
    readonly property string value: selectedOption ? selectedOption.id : ""
    readonly property var matches: options.filter(option => option.name.toLowerCase().includes(query.trim().toLowerCase())
        || option.id.toLowerCase().includes(query.trim().toLowerCase()))
    implicitHeight: input.implicitHeight
    implicitWidth: 240

    function openMenu(filter) {
        if (!enabled || !visible) return;
        query = filter;
        suggestions.open();
        results.currentIndex = Math.max(0, matches.findIndex(option => selectedOption && option.id === selectedOption.id));
        results.positionViewAtIndex(results.currentIndex, ListView.Contain);
    }
    function choose(option) {
        input.text = option.id === "" ? "" : option.name;
        suggestions.close();
    }
    function moveSelection(delta) {
        if (!suggestions.opened) {
            openMenu(input.text);
            return;
        }
        results.currentIndex = Math.max(0, Math.min(matches.length - 1, results.currentIndex + delta));
        results.positionViewAtIndex(results.currentIndex, ListView.Contain);
    }
    onMatchesChanged: results.currentIndex = matches.length ? 0 : -1
    onEnabledChanged: if (!enabled) suggestions.close()
    onVisibleChanged: if (!visible) suggestions.close()

    SettingsField {
        id: input
        objectName: "search-input"
        anchors.fill: parent
        theme: control.theme
        rightPadding: 44
        maximumLength: 64
        Accessible.name: control.accessibleName
        onTextEdited: control.openMenu(text)
        onActiveFocusChanged: if (!activeFocus) suggestions.close()
        onAccepted: {
            if (suggestions.opened && results.currentIndex >= 0 && control.matches.length)
                control.choose(control.matches[results.currentIndex]);
            else control.openMenu(text);
        }
        Keys.onDownPressed: control.moveSelection(1)
        Keys.onUpPressed: control.moveSelection(-1)
        Keys.onEscapePressed: event => {
            event.accepted = suggestions.opened;
            suggestions.close();
        }
        TapHandler { onTapped: control.openMenu(input.text) }
    }
    ToolButton {
        objectName: "search-toggle"
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 40
        focusPolicy: Qt.NoFocus
        Accessible.name: "Show all options"
        contentItem: Text {
            text: suggestions.opened ? "▴" : "▾"
            color: control.theme.textColor
            font.pixelSize: 16
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Item {}
        onClicked: {
            input.forceActiveFocus();
            if (suggestions.opened) suggestions.close();
            else control.openMenu("");
        }
    }
    Popup {
        id: suggestions
        objectName: "search-popup"
        y: control.height + 4
        width: control.width
        height: Math.min(240, Math.max(1, results.count) * 40) + padding * 2
        padding: 6
        popupType: Popup.Item
        focus: false
        closePolicy: Popup.CloseOnPressOutsideParent
        background: Rectangle {
            radius: 12
            color: control.theme.surface
            border.color: control.theme.raised
        }
        contentItem: Item {
            ListView {
                id: results
                objectName: "search-results"
                anchors.fill: parent
                clip: true
                model: control.matches
                highlightMoveDuration: 0
                ScrollBar.vertical: ScrollBar {}
                delegate: ItemDelegate {
                    id: result
                    required property var modelData
                    required property int index
                    objectName: "search-option-" + modelData.id
                    width: results.width
                    height: 40
                    focusPolicy: Qt.NoFocus
                    highlighted: results.currentIndex === index
                    Accessible.name: modelData.name
                    contentItem: Item {
                        Text {
                            anchors.left: parent.left; anchors.right: code.left; anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: result.modelData.name; textFormat: Text.PlainText; elide: Text.ElideRight
                            color: result.highlighted ? control.theme.accentText : control.theme.textColor
                            font.family: control.theme.uiFont; font.pixelSize: 13
                        }
                        Text {
                            id: code
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            text: result.modelData.id; textFormat: Text.PlainText
                            color: result.highlighted ? control.theme.accentText : control.theme.textColor
                            font.family: control.theme.uiFont; font.pixelSize: 11; opacity: 0.7
                        }
                    }
                    background: Rectangle {
                        radius: 8
                        color: result.highlighted ? control.theme.accent : result.hovered ? control.theme.raised : control.theme.surface
                    }
                    onClicked: control.choose(modelData)
                }
            }
            Text {
                objectName: "search-empty"
                anchors.fill: parent; anchors.leftMargin: 6
                visible: results.count === 0
                text: "No matching options"
                color: control.theme.textColor
                font.family: control.theme.uiFont; font.pixelSize: 13
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
