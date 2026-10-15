import QtQuick
import QtTest
import "../../../roles/desktop/files/shell"

Rectangle {
    id: fixture
    width: 1280; height: 800
    color: "#f4e1e7"
    readonly property string field: "general.lockPowerRequiresAuth"
    property var originalCategories: []
    property var originalSettings: []
    SettingsStore { id: store }
    ConfigurationWindow {
        id: configuration
        anchors.fill: parent
        store: store
        visible: false
        onClosed: visible = false
    }
    SignalSpy { id: closed; target: configuration; signalName: "closed" }
    SignalSpy { id: applyRequest; target: store; signalName: "applyRequested" }

    TestCase {
        name: "Configuration"
        when: windowShown
        function control(name) { return findChild(configuration, name); }
        function click(name) {
            const item = control(name);
            verify(item !== null, name);
            mouseClick(item, item.width / 2, item.height / 2);
        }
        function snapshot(revision, value) { return {revision: revision, values: {[fixture.field]: value}}; }
        function change() {
            const toggle = control("settings-lock-power");
            verify(toggle !== null);
            mouseClick(toggle, 14, toggle.height / 2);
            compare(store.dirty, true);
        }
        function initTestCase() {
            fixture.originalCategories = configuration.registry.categories;
            fixture.originalSettings = configuration.registry.settings;
        }
        function init() {
            fixture.width = 1280; fixture.height = 800;
            store.busy = false;
            store.loaded = false;
            store.sourceError = "";
            store.receive(snapshot("original", true));
            configuration.registry.categories = fixture.originalCategories;
            configuration.registry.settings = fixture.originalSettings;
            store.selectedCategory = "general";
            configuration.pendingSetting = "";
            configuration.closeAfterApply = false;
            configuration.surface = "#fff8f9";
            configuration.raised = "#ffe7eb";
            configuration.textColor = "#3d2c32";
            configuration.accent = "#bd0056";
            configuration.accentText = "#ffffff";
            configuration.visible = true;
            configuration.clearSearch();
            closed.clear(); applyRequest.clear();
            tryVerify(() => control("settings-lock-power") !== null);
            control("settings-general-scroll").highlightedSetting = "";
            tryCompare(control("settings-search"), "activeFocus", true);
            waitForRendering(configuration);
        }
        function cleanup() {
            if (configuration.confirmingClose) configuration.handleEscape();
            configuration.visible = false;
        }
        function test_search_data() {
            return [
                {tag: "category", query: " GENERAL ", count: 1},
                {tag: "aliases and whitespace", query: "  LOGIN   password ", count: 1},
                {tag: "multiple terms", query: "lock restart", count: 1},
                {tag: "no matches", query: "timezone", count: 0},
                {tag: "all terms required", query: "power nonexistent", count: 0},
                {tag: "empty query", query: "  ", count: 0}
            ];
        }
        function test_search(data) {
            configuration.query = data.query;
            compare(configuration.results.length, data.count);
            compare(control("settings-search-empty").visible, configuration.searching && data.count === 0);
            compare(store.dirty, false);
        }
        function test_typed_search_enter_reveals_and_focuses_control() {
            keyClick(Qt.Key_P); keyClick(Qt.Key_O); keyClick(Qt.Key_W); keyClick(Qt.Key_E); keyClick(Qt.Key_R);
            compare(configuration.query, "power");
            keyClick(Qt.Key_Return);
            compare(control("settings-lock-power").activeFocus, true);
            compare(control("settings-general-scroll").highlightedSetting, fixture.field);
            compare(configuration.query, "power");
            compare(closed.count, 0);
        }
        function test_search_does_not_discard_draft_and_escape_is_layered() {
            change();
            configuration.query = "power";
            configuration.focusSearch();
            keyClick(Qt.Key_Return);
            compare(store.draft[fixture.field], false);
            keyClick(Qt.Key_Escape);
            compare(configuration.query, "");
            compare(configuration.confirmingClose, false);
            keyClick(Qt.Key_Escape);
            tryCompare(configuration, "confirmingClose", true);
            keyClick(Qt.Key_Escape);
            tryCompare(configuration, "confirmingClose", false);
            compare(store.dirty, true);
            compare(closed.count, 0);
        }
        function test_ctrl_f_clear_and_keyboard_result_selection() {
            configuration.registry.settings = fixture.originalSettings.concat([
                {id: "test.setting", category: "general", label: "Power test", description: "Test result", keywords: "power"}
            ]);
            configuration.query = "power";
            compare(configuration.results.length, 2);
            configuration.focusSearch();
            keyClick(Qt.Key_Down);
            compare(configuration.selectedResult, 1);
            keyClick(Qt.Key_Up);
            compare(configuration.selectedResult, 0);
            keyClick(Qt.Key_Return);
            compare(control("settings-lock-power").activeFocus, true);
            keyClick(Qt.Key_F, Qt.ControlModifier);
            compare(control("settings-search").activeFocus, true);
            compare(control("settings-search").selectedText, "power");
            click("settings-search-clear");
            compare(configuration.query, "");
            compare(control("settings-search").activeFocus, true);
        }
        function test_revert_and_apply_keep_window_open() {
            compare(control("settings-apply").enabled, false);
            change();
            compare(control("settings-apply").enabled, true);
            click("settings-revert");
            compare(store.dirty, false);
            compare(control("settings-lock-power").checked, true);
            change();
            click("settings-apply");
            compare(applyRequest.count, 1);
            compare(applyRequest.signalArguments[0][0].changes[fixture.field], false);
            compare(store.busy, true);
            compare(control("settings-apply").enabled, false);
            compare(control("settings-revert").enabled, false);
            configuration.requestClose();
            compare(closed.count, 0);
            store.finish({ok: true, snapshot: snapshot("saved", false)});
            compare(store.dirty, false);
            compare(configuration.visible, true);
            compare(closed.count, 0);
        }
        function test_close_choices_data() { return [{tag: "Stay", choice: "stay"}, {tag: "Discard", choice: "discard"}, {tag: "Apply", choice: "apply"}]; }
        function test_close_choices(data) {
            change();
            click("configuration-close");
            tryCompare(configuration, "confirmingClose", true);
            click("settings-close-" + data.choice);
            tryCompare(configuration, "confirmingClose", false);
            if (data.choice === "stay") {
                compare(store.dirty, true);
                compare(closed.count, 0);
            } else if (data.choice === "discard") {
                compare(store.dirty, false);
                compare(closed.count, 1);
            } else {
                compare(store.busy, true);
                compare(closed.count, 0);
                store.finish({ok: true, snapshot: snapshot("saved", false)});
                compare(closed.count, 1);
            }
        }
        function test_failed_close_apply_retains_draft_and_regular_apply_stays_open() {
            change();
            configuration.requestClose();
            click("settings-close-apply");
            store.finish({ok: false, code: "io", message: "Injected failure"});
            compare(store.dirty, true);
            compare(closed.count, 0);
            compare(configuration.closeAfterApply, false);
            click("settings-apply");
            store.finish({ok: true, snapshot: snapshot("saved", false)});
            compare(closed.count, 0);
            compare(configuration.visible, true);
        }
        function test_close_choices_accept_keyboard_navigation() {
            change();
            configuration.requestClose();
            tryCompare(control("settings-close-stay"), "activeFocus", true);
            keyClick(Qt.Key_Tab);
            compare(control("settings-close-discard").activeFocus, true);
            keyClick(Qt.Key_Tab);
            compare(control("settings-close-apply").activeFocus, true);
            keyClick(Qt.Key_Space);
            compare(store.busy, true);
            compare(closed.count, 0);
            store.finish({ok: true, snapshot: snapshot("saved", false)});
            compare(closed.count, 1);
        }
        function test_external_changes_refresh_clean_form_and_preserve_dirty_draft() {
            store.receive(snapshot("external-1", false));
            compare(store.revision, "external-1");
            compare(store.draft[fixture.field], false);
            change();
            store.receive(snapshot("external-2", false));
            compare(store.revision, "external-1");
            compare(store.draft[fixture.field], true);
            compare(store.conflict, true);
            compare(store.canApply, false);
            click("settings-revert");
            compare(store.revision, "external-2");
            compare(store.draft[fixture.field], false);
            compare(store.conflict, false);
        }
        function test_invalid_values_and_source_errors_disable_apply() {
            store.edit(fixture.field, "false");
            compare(store.valid, false);
            compare(store.canApply, false);
            store.edit(fixture.field, false);
            compare(store.canApply, true);
            store.sourceError = "Unable to read settings";
            compare(store.canApply, false);
            compare(control("settings-status").text, store.sourceError);
        }
        function test_outside_click_focus_loss_and_category_unloading_preserve_draft() {
            change();
            mouseClick(configuration, 2, 2);
            compare(closed.count, 0);
            configuration.focusSearch();
            compare(store.dirty, true);
            const loader = control("settings-page-loader");
            loader.active = false;
            compare(loader.item, null);
            configuration.query = "power";
            configuration.activateResult(0);
            compare(configuration.pendingSetting, fixture.field);
            loader.active = true;
            tryCompare(configuration, "pendingSetting", "");
            compare(control("settings-lock-power").checked, false);
            compare(store.dirty, true);
            configuration.visible = false;
            configuration.visible = true;
            compare(store.draft[fixture.field], false);
        }
        function test_category_search_loads_new_page_and_retains_draft() {
            change();
            configuration.registry.categories = fixture.originalCategories.concat([
                {id: "other", title: "Other", page: fixture.originalCategories[0].page}
            ]);
            configuration.registry.settings = [Object.assign({}, fixture.originalSettings[0], {category: "other"})];
            configuration.query = "Other password";
            compare(configuration.results.length, 1);
            configuration.activateResult(0);
            tryCompare(store, "selectedCategory", "other");
            tryCompare(configuration, "pendingSetting", "");
            compare(store.draft[fixture.field], false);
            compare(control("settings-lock-power").activeFocus, true);
        }
        function test_small_screen_and_independent_scrolling_data() {
            return [{tag: "small", width: 480, height: 360}, {tag: "minimum", width: 320, height: 240}];
        }
        function test_small_screen_and_independent_scrolling(data) {
            fixture.width = data.width; fixture.height = data.height;
            store.error = "Settings changed elsewhere. Revert to reload the current values before applying changes.";
            const categories = fixture.originalCategories.slice();
            for (let index = 0; index < 40; index++) categories.push({id: "test" + index, title: "Test category " + index, page: categories[0].page});
            configuration.registry.categories = categories;
            waitForRendering(configuration);
            const frame = control("configuration-surface");
            verify(frame.x >= 0 && frame.y >= 0);
            verify(frame.x + frame.width <= configuration.width);
            verify(frame.y + frame.height <= configuration.height);
            const sidebar = control("settings-navigation");
            const form = control("settings-general-scroll");
            verify(sidebar.contentHeight > sidebar.height);
            verify(form.contentHeight > form.height);
            const search = control("settings-search");
            const searchY = search.mapToItem(configuration, 0, 0).y;
            const applyY = control("settings-apply").mapToItem(configuration, 0, 0).y;
            sidebar.contentY = sidebar.contentHeight - sidebar.height;
            compare(form.contentY, 0);
            form.contentY = form.contentHeight - form.height;
            verify(form.contentY > 0);
            compare(search.mapToItem(configuration, 0, 0).y, searchY);
            compare(control("settings-apply").mapToItem(configuration, 0, 0).y, applyY);
            verify(applyY + control("settings-apply").height <= frame.y + frame.height);
        }
        function test_light_and_dark_rendering() {
            waitForRendering(configuration);
            const light = grabImage(fixture);
            light.save("/tmp/archsetup-configuration-light.png");
            configuration.surface = "#21161c";
            configuration.raised = "#35242c";
            configuration.textColor = "#f9e2e8";
            configuration.accent = "#ffb1c8";
            configuration.accentText = "#56122e";
            waitForRendering(configuration);
            const dark = grabImage(fixture);
            verify(!dark.equals(light));
            dark.save("/tmp/archsetup-configuration-dark.png");
        }
    }
}
