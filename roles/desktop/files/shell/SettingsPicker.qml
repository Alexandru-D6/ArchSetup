pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: picker
    required property var theme
    property var items: []
    property string value: ""
    property string placeholder: "Search…"
    property string choicePlaceholder: "Choose…"
    property alias query: search.text
    readonly property var matches: {
        const terms = query.toLowerCase().trim().split(/\s+/).filter(Boolean);
        return items.filter(item => terms.every(term => (item.id + " " + item.name).toLowerCase().includes(term)));
    }
    signal selected(string id)
    spacing: 8
    function focusPrimary() { search.forceActiveFocus(); }
    SettingsField {
        id: search
        objectName: picker.objectName + "-search"
        theme: picker.theme
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        placeholderText: picker.placeholder
        Accessible.name: placeholderText
    }
    SettingsComboBox {
        objectName: picker.objectName + "-choice"
        theme: picker.theme
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        model: picker.matches
        currentIndex: picker.matches.findIndex(item => item.id === picker.value)
        displayText: picker.items.find(item => item.id === picker.value)?.name || (picker.matches.length ? picker.choicePlaceholder : "No matching choices")
        Accessible.name: picker.choicePlaceholder
        onActivated: if (currentIndex >= 0) picker.selected(currentValue)
    }
}
