pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FocusScope {
    id: configuration
    required property var store
    property string uiFont: "DejaVu Sans"
    property color surface: "#fff8f9"
    property color raised: "#ffe7eb"
    property color textColor: "#3d2c32"
    property color accent: "#bd0056"
    property color accentText: "#ffffff"
    property bool inset: true
    property alias query: search.text
    property alias registry: registry
    property alias frameItem: frame
    property int selectedResult: 0
    property string pendingSetting: ""
    property bool closeAfterApply: false
    readonly property bool searching: query.trim().length > 0
    readonly property var results: registry.search(query)
    readonly property bool confirmingClose: closeDialog.visible
    readonly property var loadedPage: pageLoader.item
    signal closed()

    function focusSearch() { search.forceActiveFocus(); }
    function clearSearch() { search.clear(); focusSearch(); }
    function focusForm() { forceActiveFocus(); }
    function loadCategory() {
        const category = registry.category(store.selectedCategory);
        if (category) pageLoader.setSource(category.page, {store: store, registry: registry, theme: configuration});
    }
    function revealPending() {
        if (pendingSetting && pageLoader.status === Loader.Ready && loadedPage.revealSetting(pendingSetting)) pendingSetting = "";
    }
    function activateResult(index) {
        if (index < 0 || index >= results.length) return;
        selectedResult = index;
        pendingSetting = results[index].id;
        store.selectedCategory = results[index].category;
        revealPending();
    }
    function moveResult(delta) {
        if (!searching || !results.length) return;
        selectedResult = (selectedResult + delta + results.length) % results.length;
        navigation.positionViewAtIndex(selectedResult, ListView.Contain);
    }
    function searchKey(event) {
        if (event.key === Qt.Key_Down) moveResult(1);
        else if (event.key === Qt.Key_Up) moveResult(-1);
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && searching) activateResult(selectedResult);
        else return;
        event.accepted = true;
    }
    function requestClose() {
        if (store.busy) return;
        if (store.dirty) closeDialog.open();
        else closed();
    }
    function handleEscape() {
        if (closeDialog.visible) closeDialog.reject();
        else if (query.length) clearSearch();
        else requestClose();
    }
    Component.onCompleted: loadCategory()
    onQueryChanged: { selectedResult = 0; navigation.contentY = 0; }
    onVisibleChanged: if (visible) Qt.callLater(focusSearch)
    Connections {
        target: configuration.store
        function onSelectedCategoryChanged() { configuration.loadCategory(); }
        function onAppliedSuccessfully() {
            if (configuration.closeAfterApply) { configuration.closeAfterApply = false; configuration.closed(); }
        }
        function onBusyChanged() {
            if (!configuration.store.busy && configuration.store.error) configuration.closeAfterApply = false;
        }
        function onErrorChanged() { if (configuration.store.error) configuration.closeAfterApply = false; }
    }
    Keys.onEscapePressed: handleEscape()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
            focusSearch(); search.selectAll(); event.accepted = true;
        }
    }

    SettingsRegistry { id: registry }
    CenteredWindowFrame {
        id: frame
        objectName: "configuration-surface"
        title: "Configuration"
        closeObjectName: "configuration-close"
        closeEnabled: !configuration.store.busy
        inset: configuration.inset
        color: configuration.surface
        raised: configuration.raised
        textColor: configuration.textColor
        accent: configuration.accent
        accentText: configuration.accentText
        uiFont: configuration.uiFont
        onCloseRequested: configuration.requestClose()
        ColumnLayout {
            anchors.fill: parent
            spacing: 14
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: frame.width < 600 ? 10 : 24
                ColumnLayout {
                    Layout.preferredWidth: Math.max(112, Math.min(260, frame.width * 0.27))
                    Layout.minimumWidth: Layout.preferredWidth
                    Layout.maximumWidth: Layout.preferredWidth
                    Layout.fillHeight: true
                    spacing: 12
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        TextField {
                            id: search
                            objectName: "settings-search"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            implicitHeight: 42
                            leftPadding: 12; rightPadding: 12
                            placeholderText: "Search settings…"
                            Accessible.name: "Search settings"
                            color: configuration.textColor
                            placeholderTextColor: Qt.rgba(configuration.textColor.r, configuration.textColor.g, configuration.textColor.b, 0.65)
                            selectionColor: configuration.accent
                            selectedTextColor: configuration.accentText
                            font.family: configuration.uiFont
                            font.pixelSize: 13
                            selectByMouse: true
                            Keys.onPressed: event => configuration.searchKey(event)
                            background: Rectangle {
                                radius: 14
                                color: configuration.raised
                                border.width: search.activeFocus ? 2 : 0
                                border.color: configuration.accent
                            }
                        }
                        SettingsButton {
                            objectName: "settings-search-clear"
                            theme: configuration
                            visible: configuration.query.length > 0
                            text: "×"
                            Accessible.name: "Clear settings search"
                            onClicked: configuration.clearSearch()
                        }
                    }
                    ListView {
                        id: navigation
                        objectName: "settings-navigation"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 6
                        boundsBehavior: Flickable.StopAtBounds
                        model: configuration.searching ? configuration.results : registry.categories
                        currentIndex: configuration.searching ? configuration.selectedResult : registry.categories.findIndex(item => item.id === configuration.store.selectedCategory)
                        section.property: configuration.searching ? "categoryTitle" : ""
                        section.delegate: Text {
                            required property string section
                            text: section
                            color: configuration.textColor
                            font.family: configuration.uiFont
                            font.pixelSize: 12
                            topPadding: 8; bottomPadding: 8
                        }
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        Keys.onPressed: event => configuration.searchKey(event)
                        delegate: Button {
                            id: entry
                            required property var modelData
                            required property int index
                            readonly property bool selected: index === navigation.currentIndex
                            objectName: "settings-nav-" + modelData.id
                            width: navigation.width - 10
                            padding: 12
                            text: configuration.searching ? modelData.label : modelData.title
                            Accessible.name: text
                            onClicked: {
                                if (configuration.searching) configuration.activateResult(index);
                                else configuration.store.selectedCategory = modelData.id;
                            }
                            background: Rectangle {
                                radius: 14
                                color: entry.selected || entry.hovered || entry.activeFocus ? configuration.raised : "transparent"
                                border.width: entry.activeFocus ? 2 : 0
                                border.color: configuration.accent
                            }
                            contentItem: Text {
                                text: entry.text
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                color: configuration.textColor
                                font.family: configuration.uiFont
                                font.pixelSize: 13
                            }
                        }
                        Text {
                            objectName: "settings-search-empty"
                            visible: configuration.searching && !configuration.results.length
                            width: parent.width - 10
                            text: "No matching settings"
                            wrapMode: Text.Wrap
                            color: configuration.textColor
                            opacity: 0.7
                            font.family: configuration.uiFont
                            font.pixelSize: 13
                        }
                    }
                }
                Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: configuration.raised }
                Loader {
                    id: pageLoader
                    objectName: "settings-page-loader"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 0
                    onLoaded: Qt.callLater(configuration.revealPending)
                }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: configuration.raised }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    id: changeStatus
                    objectName: "settings-status"
                    text: configuration.store.sourceError || configuration.store.error || (configuration.store.busy ? "Applying changes…" : configuration.store.conflict ? "Settings changed elsewhere. Revert to reload." : configuration.store.dirty ? "Unsaved changes" : configuration.store.notice || (configuration.store.loaded ? "All changes saved" : "Loading settings…"))
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: configuration.textColor
                    font.family: configuration.uiFont
                    font.pixelSize: 12
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                    HoverHandler { id: statusHover }
                    ToolTip.visible: statusHover.hovered && changeStatus.truncated
                    ToolTip.text: text
                }
                SettingsButton {
                    objectName: "settings-revert"
                    theme: configuration
                    text: "Revert"
                    enabled: configuration.store.loaded && !configuration.store.busy && (configuration.store.dirty || configuration.store.conflict)
                    onClicked: configuration.store.revert()
                }
                SettingsButton {
                    objectName: "settings-apply"
                    theme: configuration
                    text: "Apply"
                    primary: true
                    enabled: configuration.store.canApply
                    onClicked: configuration.store.apply()
                }
            }
        }
    }
    Dialog {
        id: closeDialog
        objectName: "settings-close-dialog"
        parent: configuration
        anchors.centerIn: parent
        width: Math.min(450, configuration.width - 24)
        padding: 20
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape
        background: Rectangle { color: configuration.surface; radius: 20; border.width: 1; border.color: configuration.accent }
        onClosed: configuration.focusForm()
        onOpened: stayButton.forceActiveFocus()
        contentItem: ColumnLayout {
            spacing: 16
            Text {
                text: "Save changes before closing?"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: configuration.textColor
                font.family: configuration.uiFont
                font.pixelSize: 18
            }
            Text {
                text: "Apply your changes, discard them, or stay in Configuration."
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: configuration.textColor
                font.family: configuration.uiFont
                font.pixelSize: 13
            }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                SettingsButton {
                    id: stayButton
                    objectName: "settings-close-stay"
                    theme: configuration
                    text: "Stay"
                    onClicked: closeDialog.reject()
                }
                SettingsButton {
                    objectName: "settings-close-discard"
                    theme: configuration
                    text: "Discard"
                    onClicked: { configuration.store.revert(); closeDialog.close(); configuration.closed(); }
                }
                SettingsButton {
                    objectName: "settings-close-apply"
                    theme: configuration
                    text: "Apply"
                    primary: true
                    enabled: configuration.store.canApply
                    onClicked: {
                        configuration.closeAfterApply = true;
                        closeDialog.close();
                        if (!configuration.store.apply()) configuration.closeAfterApply = false;
                    }
                }
            }
        }
    }
}
