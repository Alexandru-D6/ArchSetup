pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: editor
    required property var theme
    property var layouts: []
    property var catalog: []
    property int maximumLayouts: 4
    property string activeLayout: ""
    property string newLayout: ""
    property string newVariant: ""
    readonly property var newVariants: catalog.find(item => item.id === newLayout)?.variants || [{id: "", name: "Default"}]
    readonly property bool alreadyAdded: layouts.some(item => item.layout === newLayout && item.variant === newVariant)
    signal edited(var layouts)
    spacing: 12
    function focusPrimary() { addPicker.focusPrimary(); }
    function replaceVariant(index, variant) {
        const value = layouts.map(item => Object.assign({}, item));
        value[index].variant = variant;
        edited(value);
    }
    function move(index, delta) {
        const value = layouts.slice();
        const item = value.splice(index, 1)[0];
        value.splice(index + delta, 0, item);
        edited(value);
    }
    function remove(index) { edited(layouts.filter((_, position) => position !== index)); }
    function add() {
        if (!newLayout || alreadyAdded || layouts.length >= maximumLayouts) return;
        edited(layouts.concat([{layout: newLayout, variant: newVariant}]));
    }
    Repeater {
        model: editor.layouts
        ColumnLayout {
            id: entry
            required property int index
            required property var modelData
            Layout.fillWidth: true
            spacing: 6
            GridLayout {
                Layout.fillWidth: true
                columns: width >= 300 ? 2 : 1
                Text {
                    text: (entry.index + 1) + ". " + (editor.catalog.find(item => item.id === entry.modelData.layout)?.name || entry.modelData.layout)
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    wrapMode: Text.Wrap
                    color: editor.theme.textColor
                    font.family: editor.theme.uiFont
                    font.pixelSize: 13
                }
                RowLayout {
                    spacing: 4
                    SettingsButton {
                        objectName: "keyboard-up-" + entry.index
                        theme: editor.theme; text: "↑"
                        Accessible.name: "Move layout up"
                        enabled: entry.index > 0
                        onClicked: editor.move(entry.index, -1)
                    }
                    SettingsButton {
                        objectName: "keyboard-down-" + entry.index
                        theme: editor.theme; text: "↓"
                        Accessible.name: "Move layout down"
                        enabled: entry.index < editor.layouts.length - 1
                        onClicked: editor.move(entry.index, 1)
                    }
                    SettingsButton {
                        objectName: "keyboard-remove-" + entry.index
                        theme: editor.theme; text: "×"
                        Accessible.name: "Remove layout"
                        enabled: editor.layouts.length > 1
                        onClicked: editor.remove(entry.index)
                    }
                }
            }
            SettingsComboBox {
                objectName: "keyboard-variant-" + entry.index
                theme: editor.theme
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                model: editor.catalog.find(item => item.id === entry.modelData.layout)?.variants || [{id: "", name: "Default"}]
                currentIndex: model.findIndex(item => item.id === entry.modelData.variant)
                Accessible.name: "Variant for " + entry.modelData.layout
                onActivated: editor.replaceVariant(entry.index, currentValue)
            }
        }
    }
    SettingsPicker {
        id: addPicker
        objectName: "keyboard-add-layout"
        Layout.fillWidth: true
        theme: editor.theme
        items: editor.catalog
        value: editor.newLayout
        placeholder: "Search languages or layout codes…"
        choicePlaceholder: "Choose a layout to add"
        enabled: editor.layouts.length < editor.maximumLayouts
        onSelected: id => { editor.newLayout = id; editor.newVariant = ""; }
    }
    SettingsComboBox {
        objectName: "keyboard-add-variant"
        theme: editor.theme
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        model: editor.newVariants
        currentIndex: model.findIndex(item => item.id === editor.newVariant)
        enabled: editor.newLayout !== "" && editor.layouts.length < editor.maximumLayouts
        Accessible.name: "Variant for the new layout"
        onActivated: editor.newVariant = currentValue
    }
    SettingsButton {
        objectName: "keyboard-add"
        theme: editor.theme
        text: editor.alreadyAdded ? "Already added" : "Add layout"
        enabled: editor.newLayout !== "" && !editor.alreadyAdded && editor.layouts.length < editor.maximumLayouts
        onClicked: editor.add()
    }
    Text {
        text: "Active: " + (editor.activeLayout || "Available after applying in a desktop session") + " · Super+Space switches layouts"
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: editor.theme.textColor
        font.family: editor.theme.uiFont
        font.pixelSize: 12
    }
    SettingsField {
        objectName: "keyboard-test"
        theme: editor.theme
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        placeholderText: "Test the applied keyboard layout…"
        Accessible.name: "Test the applied keyboard layout"
    }
}
