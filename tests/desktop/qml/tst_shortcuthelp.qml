import QtQuick
import QtTest
import "../../../roles/desktop/files/shell"

Rectangle {
    id: fixture
    width: 1280
    height: 800
    color: "#f4e1e7"
    property var productionBindings: []
    readonly property var sampleBindings: [
        {key: "SUPER + Return", description: "Terminal", category: "Applications", action: "terminal"},
        {key: "SUPER + W", description: "Browser", category: "Applications", action: "browser"},
        {key: "SUPER + SHIFT + S", description: "Screen snip", category: "Utilities", action: "screenshot"},
        {key: "CTRL + SUPER + SHIFT + S", description: "Screen snip", category: "Utilities", action: "screenshot"},
        {key: "SUPER + S", description: "Scratch workspace", category: "Workspaces"},
        {key: "SUPER + SHIFT + D", description: "Light / dark theme", category: "Shell"},
        {key: "SUPER + Left", description: "Focus left", category: "Windows"}
    ]
    MouseArea { anchors.fill: parent; onClicked: help.cancelled() }
    ShortcutHelp {
        id: help
        anchors.fill: parent
        visible: false
        onCancelled: visible = false
    }
    SignalSpy { id: cancellation; target: help; signalName: "cancelled" }

    TestCase {
        name: "ShortcutHelp"
        when: windowShown
        function search() { return findChild(help, "shortcuts-search"); }
        function scroll() { return findChild(help, "shortcuts-scroll"); }
        function row(key) { return findChild(help, "shortcut-row-" + key); }
        function initTestCase() {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../../../roles/desktop/files/shortcuts.json"), false);
            request.send();
            fixture.productionBindings = JSON.parse(request.responseText);
            verify(fixture.productionBindings.length > 200);
        }
        function init() {
            fixture.width = 1280;
            fixture.height = 800;
            help.bindings = fixture.sampleBindings;
            help.loadError = "";
            help.surface = "#fff8f9";
            help.raised = "#ffe7eb";
            help.textColor = "#3d2c32";
            help.accent = "#bd0056";
            help.visible = true;
            help.clearSearch();
            cancellation.clear();
            tryCompare(search(), "activeFocus", true);
            waitForRendering(help);
        }
        function cleanup() { help.visible = false; }

        function test_typing_removes_rows_and_empty_categories() {
            compare(help.matchCount, 7);
            compare(help.categories.length, 5);
            keyClick(Qt.Key_S);
            keyClick(Qt.Key_N);
            keyClick(Qt.Key_I);
            keyClick(Qt.Key_P);
            compare(help.query, "snip");
            compare(help.matchCount, 2);
            compare(help.categories.length, 1);
            verify(row("SUPER + SHIFT + S") !== null);
            verify(row("CTRL + SUPER + SHIFT + S") !== null);
            compare(row("SUPER + W"), null);
            compare(findChild(help, "shortcut-category-Applications"), null);
            compare(findChild(help, "shortcut-category-Workspaces"), null);
        }
        function test_search_matches_data() {
            return [
                {tag: "key combination", query: "sUpEr +  shift + s", keys: ["SUPER + SHIFT + S", "CTRL + SUPER + SHIFT + S"]},
                {tag: "multiple terms", query: "  CTRL   super shift s ", keys: ["CTRL + SUPER + SHIFT + S"]},
                {tag: "displayed key name", query: "enter", keys: ["SUPER + Return"]},
                {tag: "raw key name", query: "return", keys: ["SUPER + Return"]},
                {tag: "category", query: "utilities", keys: ["SUPER + SHIFT + S", "CTRL + SUPER + SHIFT + S"]},
                {tag: "description", query: "focus left", keys: ["SUPER + Left"]},
                {tag: "partial word", query: "term", keys: ["SUPER + Return"]},
                {tag: "action", query: "screenshot", keys: ["SUPER + SHIFT + S", "CTRL + SUPER + SHIFT + S"]}
            ];
        }
        function test_search_matches(data) {
            help.query = data.query;
            compare(help.matches.map(binding => binding.key), data.keys);
            for (const key of data.keys) verify(row(key) !== null);
            for (const binding of fixture.sampleBindings) {
                if (!data.keys.includes(binding.key)) compare(row(binding.key), null);
            }
        }
        function test_clear_restores_all_rows_and_focus() {
            help.query = "snip";
            const clear = findChild(help, "shortcuts-clear");
            verify(clear.visible);
            mouseClick(clear, clear.width / 2, clear.height / 2);
            compare(help.query, "");
            compare(help.matchCount, 7);
            compare(help.categories.length, 5);
            compare(search().activeFocus, true);
            verify(!clear.visible);
            for (const binding of fixture.sampleBindings) verify(row(binding.key) !== null);
        }
        function test_no_matches_and_empty_map() {
            help.query = "<b>does not exist</b>";
            compare(help.matchCount, 0);
            compare(help.categories.length, 0);
            const message = findChild(help, "shortcuts-empty");
            verify(message.visible);
            compare(message.text, "No matching shortcuts");
            help.bindings = [];
            compare(message.text, "No shortcuts available");
            help.loadError = "Could not load shortcuts";
            compare(message.text, "Could not load shortcuts");
        }
        function test_keyboard_clear_and_refocus() {
            help.query = "snip";
            const close = findChild(help, "shortcuts-close");
            close.forceActiveFocus();
            keyClick(Qt.Key_F, Qt.ControlModifier);
            compare(search().activeFocus, true);
            compare(search().selectedText, "snip");
            keyClick(Qt.Key_Backspace);
            compare(help.query, "");
            compare(help.matchCount, 7);
            keyClick(Qt.Key_Return);
            compare(cancellation.count, 0);
            compare(help.visible, true);
        }
        function test_escape_and_close_cancel_data() { return [{tag: "escape", escape: true}, {tag: "close", escape: false}]; }
        function test_escape_and_close_cancel(data) {
            help.query = "snip";
            if (data.escape) keyClick(Qt.Key_Escape);
            else {
                const close = findChild(help, "shortcuts-close");
                mouseClick(close, close.width / 2, close.height / 2);
            }
            compare(cancellation.count, 1);
            compare(help.visible, false);
        }
        function test_only_background_clicks_cancel() {
            const binding = row("SUPER + Return");
            mouseClick(binding, binding.width / 2, binding.height / 2);
            compare(cancellation.count, 0);
            mouseClick(help, 2, 2);
            compare(cancellation.count, 1);
            compare(help.visible, false);
        }
        function test_reopening_resets_search() {
            help.query = "snip";
            help.visible = false;
            help.visible = true;
            compare(help.query, "");
            compare(help.matchCount, 7);
            tryCompare(search(), "activeFocus", true);
        }
        function test_binding_updates_reapply_current_search() {
            help.query = "snip";
            help.bindings = [{key: "Print", description: "New screen snip", category: "Capture"}];
            compare(help.matchCount, 1);
            verify(row("Print") !== null);
            compare(row("SUPER + SHIFT + S"), null);
            compare(findChild(help, "shortcut-category-Utilities"), null);
            verify(findChild(help, "shortcut-category-Capture") !== null);
        }
        function test_small_screen_wraps_keys_and_descriptions() {
            fixture.width = 320;
            fixture.height = 240;
            help.bindings = [{key: "CTRL + SUPER + SHIFT + ALT + Delete", description: "A long shortcut description that should wrap without hiding the keys", category: "A long category name"}];
            waitForRendering(help);
            compare(help.columnCount, 1);
            const surface = findChild(help, "shortcuts-surface");
            verify(surface.x >= 0 && surface.y >= 0);
            verify(surface.x + surface.width <= help.width);
            verify(surface.y + surface.height <= help.height);
            compare(scroll().contentWidth, scroll().width);
            const binding = row("CTRL + SUPER + SHIFT + ALT + Delete");
            verify(binding.height > 50);
            const point = binding.mapToItem(surface, 0, 0);
            verify(point.x >= 0 && point.x + binding.width <= surface.width);
            verify(search().width > 100);
        }
        function test_production_map_filters_and_scrolls() {
            help.bindings = fixture.productionBindings;
            compare(help.matchCount, fixture.productionBindings.length);
            for (const binding of fixture.productionBindings) verify(row(binding.key) !== null, binding.key);
            waitForRendering(help);
            verify(scroll().contentHeight > scroll().height);
            scroll().contentY = scroll().contentHeight - scroll().height;
            verify(scroll().contentY > 0);
            help.query = "Super + Shift + S";
            compare(scroll().contentY, 0);
            compare(help.matchCount, 2);
            compare(help.categories.length, 1);
            verify(row("SUPER + SHIFT + S") !== null);
            compare(row("SUPER + S"), null);
            help.query = "screen snip";
            compare(help.matchCount, 3);
            verify(row("CTRL + SHIFT + Print") !== null);
        }
        function test_production_map_rendering() {
            help.bindings = fixture.productionBindings;
            waitForRendering(help);
            const light = grabImage(fixture);
            light.save("/tmp/archsetup-shortcuts-light.png");
            help.query = "screen snip";
            waitForRendering(help);
            const keycap = findChild(row("SUPER + SHIFT + S"), "shortcut-keycap-Super");
            // Wait for the replacement delegates to paint after filtering.
            tryVerify(() => grabImage(keycap).alpha(2, keycap.height / 2) === 255);
            waitForRendering(help);
            const filtered = grabImage(fixture);
            verify(!filtered.equals(light));
            filtered.save("/tmp/archsetup-shortcuts-search.png");
            help.surface = "#21161c";
            help.raised = "#35242c";
            help.textColor = "#f9e2e8";
            help.accent = "#ffb1c8";
            waitForRendering(help);
            const dark = grabImage(fixture);
            verify(!dark.equals(filtered));
            dark.save("/tmp/archsetup-shortcuts-dark.png");
        }
    }
}
