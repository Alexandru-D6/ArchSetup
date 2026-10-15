pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FocusScope {
    id: help
    property var bindings: []
    property string loadError: ""
    property string uiFont: "DejaVu Sans"
    property color surface: "#fff8f9"
    property color raised: "#ffe7eb"
    property color textColor: "#3d2c32"
    property color accent: "#bd0056"
    property alias query: search.text
    readonly property int matchCount: matches.length
    readonly property int columnCount: Math.min(Math.max(1, Math.floor((scroll.width + 18) / 380)), Math.max(1, categories.length), 3)
    readonly property var matches: {
        const terms = normalize(query).split(/\s+/).filter(term => term.length > 0);
        return bindings.filter(binding => {
            const text = normalize(binding.key + " " + keyLabels(binding.key).join(" ") + " " + binding.description + " " + (binding.category || "Other") + " " + (binding.action || ""));
            // A single key such as S must not match the S in every Super modifier.
            const words = text.split(/[\s:]+/);
            return terms.every(term => term.length === 1 ? words.includes(term) : text.includes(term));
        });
    }
    readonly property var categories: {
        const groups = [];
        for (const binding of matches) {
            const name = binding.category || "Other";
            let group = groups.find(item => item.name === name);
            if (!group) { group = {name: name, bindings: []}; groups.push(group); }
            group.bindings.push(binding);
        }
        return groups;
    }
    readonly property var columns: {
        const result = [];
        const sizes = [];
        for (let index = 0; index < columnCount; index++) { result.push([]); sizes.push(0); }
        for (const category of categories) {
            const index = sizes.indexOf(Math.min.apply(null, sizes));
            result[index].push(category);
            sizes[index] += category.bindings.length + 2;
        }
        return result;
    }
    signal cancelled()

    function normalize(text) { return text.toLowerCase().replace(/\+/g, " ").replace(/\s+/g, " ").trim(); }
    function keyLabels(key) {
        const names = {
            super: "Super", ctrl: "Ctrl", alt: "Alt", shift: "Shift", return: "Enter",
            escape: "Esc", space: "Space", tab: "Tab", print: "Print", delete: "Delete",
            left: "←", right: "→", up: "↑", down: "↓", page_up: "Page Up", page_down: "Page Down",
            slash: "/", comma: ",", period: ".", minus: "−", equal: "=", bracketleft: "[", bracketright: "]",
            super_l: "Left Super", super_r: "Right Super", mouse_up: "Scroll up", mouse_down: "Scroll down",
            "mouse:272": "Left mouse", "mouse:273": "Right mouse", "mouse:275": "Mouse back"
        };
        return key.split("+").map(part => {
            const label = part.trim();
            return names[label.toLowerCase()] || label;
        });
    }
    function focusSearch() { search.forceActiveFocus(); }
    function clearSearch() { search.clear(); focusSearch(); }
    onQueryChanged: scroll.contentY = 0
    onVisibleChanged: if (visible) { clearSearch(); scroll.contentY = 0; }
    Keys.onEscapePressed: cancelled()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
            focusSearch(); search.selectAll(); event.accepted = true;
        }
    }

    CenteredWindowFrame {
        id: surface
        objectName: "shortcuts-surface"
        title: "Shortcuts"
        closeObjectName: "shortcuts-close"
        color: help.surface
        raised: help.raised
        textColor: help.textColor
        accent: help.accent
        uiFont: help.uiFont
        onCloseRequested: help.cancelled()

        ColumnLayout {
            anchors.fill: parent
            spacing: 14
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                TextField {
                    id: search
                    objectName: "shortcuts-search"
                    Layout.fillWidth: true
                    implicitHeight: 42
                    leftPadding: 14; rightPadding: 14
                    placeholderText: "Search shortcuts…"
                    Accessible.name: "Search shortcuts"
                    color: help.textColor
                    placeholderTextColor: Qt.rgba(help.textColor.r, help.textColor.g, help.textColor.b, 0.65)
                    selectionColor: help.accent
                    selectedTextColor: help.surface
                    font.family: help.uiFont
                    font.pixelSize: 14
                    selectByMouse: true
                    background: Rectangle {
                        radius: 14
                        color: help.raised
                        border.width: search.activeFocus ? 2 : 0
                        border.color: help.accent
                    }
                }
                Button {
                    id: clearButton
                    objectName: "shortcuts-clear"
                    visible: search.text.length > 0
                    text: "Clear"
                    Accessible.name: "Clear search"
                    padding: 10
                    implicitHeight: 38
                    onClicked: help.clearSearch()
                    background: Rectangle { radius: 14; color: help.raised; border.width: clearButton.activeFocus ? 1 : 0; border.color: help.accent }
                    contentItem: Text { text: clearButton.text; color: help.textColor; font.family: help.uiFont; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                }
            }
            Text {
                objectName: "shortcuts-count"
                text: help.query.trim() ? help.matchCount + " of " + help.bindings.length + " shortcuts" : help.bindings.length + " shortcuts · Search keys, actions or categories"
                color: help.textColor
                opacity: 0.7
                font.family: help.uiFont
                font.pixelSize: 12
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Flickable {
                    id: scroll
                    objectName: "shortcuts-scroll"
                    anchors.fill: parent
                    clip: true
                    contentWidth: width
                    contentHeight: categoryColumns.height
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    ScrollBar.vertical: ScrollBar {
                        id: scrollBar
                        policy: ScrollBar.AsNeeded
                        visible: size < 1
                        contentItem: Rectangle {
                            implicitWidth: 6; implicitHeight: 6
                            radius: 3
                            color: help.textColor
                            opacity: scrollBar.pressed ? 0.8 : 0.35
                        }
                    }
                    Row {
                        id: categoryColumns
                        width: scroll.width - 12
                        spacing: 18
                        Repeater {
                            model: help.columns
                            Column {
                                id: categoryColumn
                                required property var modelData
                                width: (categoryColumns.width - categoryColumns.spacing * (help.columnCount - 1)) / help.columnCount
                                spacing: 20
                                Repeater {
                                    model: categoryColumn.modelData
                                    Column {
                                        id: category
                                        required property var modelData
                                        objectName: "shortcut-category-" + modelData.name
                                        width: categoryColumn.width
                                        spacing: 10
                                        RowLayout {
                                            width: parent.width
                                            Text {
                                                text: category.modelData.name
                                                color: help.accent
                                                font.family: help.uiFont
                                                font.pixelSize: 18
                                                font.weight: Font.DemiBold
                                                wrapMode: Text.Wrap
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: category.modelData.bindings.length
                                                color: help.textColor
                                                opacity: 0.6
                                                font.family: help.uiFont
                                                font.pixelSize: 12
                                            }
                                        }
                                        Repeater {
                                            model: category.modelData.bindings
                                            Column {
                                                id: bindingRow
                                                required property var modelData
                                                objectName: "shortcut-row-" + modelData.key
                                                width: category.width
                                                spacing: 8
                                                Accessible.role: Accessible.StaticText
                                                Accessible.name: modelData.key + ": " + modelData.description
                                                RowLayout {
                                                    width: parent.width
                                                    spacing: 10
                                                    Flow {
                                                        id: keycaps
                                                        Layout.preferredWidth: Math.min(190, bindingRow.width * 0.54)
                                                        Layout.preferredHeight: implicitHeight
                                                        spacing: 4
                                                        Repeater {
                                                            model: help.keyLabels(bindingRow.modelData.key)
                                                            Rectangle {
                                                                id: keycap
                                                                required property string modelData
                                                                objectName: "shortcut-keycap-" + modelData
                                                                width: Math.min(keycaps.width, keyText.implicitWidth + 14)
                                                                height: 25
                                                                radius: 6
                                                                color: help.raised
                                                                Text {
                                                                    id: keyText
                                                                    anchors.fill: parent
                                                                    anchors.margins: 4
                                                                    text: keycap.modelData
                                                                    color: help.textColor
                                                                    font.family: help.uiFont
                                                                    font.pixelSize: 11
                                                                    horizontalAlignment: Text.AlignHCenter
                                                                    verticalAlignment: Text.AlignVCenter
                                                                    elide: Text.ElideRight
                                                                }
                                                            }
                                                        }
                                                    }
                                                    Text {
                                                        text: bindingRow.modelData.description
                                                        textFormat: Text.PlainText
                                                        color: help.textColor
                                                        font.family: help.uiFont
                                                        font.pixelSize: 12
                                                        wrapMode: Text.Wrap
                                                        Layout.fillWidth: true
                                                    }
                                                }
                                                Rectangle { width: parent.width; height: 1; color: help.raised }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Text {
                    objectName: "shortcuts-empty"
                    anchors.centerIn: parent
                    width: parent.width
                    visible: help.matchCount === 0
                    text: help.loadError || (help.bindings.length === 0 ? "No shortcuts available" : "No matching shortcuts")
                    textFormat: Text.PlainText
                    color: help.textColor
                    font.family: help.uiFont
                    font.pixelSize: 16
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}
