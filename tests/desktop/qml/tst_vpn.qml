import QtQuick
import QtTest
import "../../../roles/desktop/files/shell"

Item {
    width: 420; height: 760
    QtObject {
        id: theme
        property string uiFont: "DejaVu Sans"
        property color raised: "#ffe7eb"
        property color surface: "#fff7f9"
        property color textColor: "#3d2c32"
        property color accent: "#bd0056"
        property color accentText: "white"
    }
    VpnPanel { id: panel; width: parent.width; theme: theme }
    SignalSpy { id: request; target: panel; signalName: "controlRequested" }
    SignalSpy { id: signin; target: panel; signalName: "signinRequested" }
    SignalSpy { id: refresh; target: panel; signalName: "refreshRequested" }
    SignalSpy { id: provider; target: panel; signalName: "providerRequested" }
    TestCase {
        name: "VpnPanel"; when: windowShown
        function init() {
            panel.snapshot = {vpnReady: true, vpnConnected: false, vpnStatus: "disconnected", vpnCountries: [
                {id: "ES", name: "Spain"}, {id: "SE", name: "Sweden"},
                {id: "CH", name: "Switzerland"}, {id: "US", name: "United States"}
            ]};
            panel.busy = false; panel.error = ""; panel.operation = "";
            findChild(panel, "vpn-country").text = "";
            request.clear(); signin.clear(); refresh.clear(); provider.clear(); wait(10);
        }
        function cleanup() {
            findChild(panel, "search-popup").close();
            findChild(panel, "search-input").focus = false;
        }
        function search(text) {
            const input = findChild(panel, "search-input");
            input.forceActiveFocus();
            keyClick(Qt.Key_A, Qt.ControlModifier);
            keyClick(Qt.Key_Backspace);
            for (const letter of text) keyClick(letter);
            wait(10);
        }
        function test_fastest_and_country_connections() {
            const button = findChild(panel, "vpn-connect");
            mouseClick(button); compare(Array.from(request.signalArguments[0]), ["connect", ""]);
            findChild(panel, "vpn-country").text = "United States";
            mouseClick(button); compare(Array.from(request.signalArguments[1]), ["connect", "US"]);
            findChild(panel, "vpn-country").text = "es";
            mouseClick(button); compare(Array.from(request.signalArguments[2]), ["connect", "ES"]);
            findChild(panel, "vpn-country").text = "Spa"; verify(!button.enabled);
            findChild(panel, "vpn-country").text = "--random"; verify(!button.enabled);
            panel.busy = true; findChild(panel, "vpn-country").text = "ES"; verify(!button.enabled);
        }
        function test_dropdown_filters_names_and_codes_as_you_type() {
            const results = findChild(panel, "search-results");
            mouseClick(findChild(panel, "search-toggle"));
            tryCompare(findChild(panel, "search-popup"), "opened", true);
            compare(results.count, 5);
            search("sW"); compare(results.count, 2);
            keyClick("e"); compare(results.count, 1);
            compare(results.itemAtIndex(0).modelData.id, "SE");
            search("cH"); compare(results.count, 1);
            compare(results.itemAtIndex(0).modelData.name, "Switzerland");
            mouseClick(results.itemAtIndex(0));
            compare(findChild(panel, "vpn-country").text, "Switzerland");
            compare(findChild(panel, "vpn-country").value, "CH");
            tryCompare(findChild(panel, "search-popup"), "opened", false);
            compare(request.count, 0);
            mouseClick(findChild(panel, "vpn-connect"));
            compare(Array.from(request.signalArguments[0]), ["connect", "CH"]);
        }
        function test_keyboard_selection_and_escape_do_not_connect() {
            search("sw");
            const results = findChild(panel, "search-results");
            compare(results.currentIndex, 0);
            keyClick(Qt.Key_Down); compare(results.currentIndex, 1);
            keyClick(Qt.Key_Up); compare(results.currentIndex, 0);
            keyClick(Qt.Key_Down); keyClick(Qt.Key_Return);
            compare(findChild(panel, "vpn-country").text, "Switzerland");
            tryCompare(findChild(panel, "search-popup"), "opened", false);
            compare(request.count, 0);
            search("sp"); keyClick(Qt.Key_Escape);
            tryCompare(findChild(panel, "search-popup"), "opened", false);
            compare(findChild(panel, "vpn-country").text, "sp");
            compare(request.count, 0);
        }
        function test_empty_results_clearing_and_fastest_selection() {
            search("zzzz");
            compare(findChild(panel, "search-results").count, 0);
            verify(findChild(panel, "search-empty").visible);
            verify(!findChild(panel, "vpn-connect").enabled);
            keyClick(Qt.Key_Return); compare(request.count, 0);
            search("");
            compare(findChild(panel, "search-results").count, 5);
            verify(findChild(panel, "vpn-connect").enabled);
            keyClick(Qt.Key_Return);
            compare(findChild(panel, "vpn-country").value, "");
            tryCompare(findChild(panel, "search-popup"), "opened", false);
            mouseClick(findChild(panel, "vpn-connect"));
            compare(Array.from(request.signalArguments[0]), ["connect", ""]);
        }
        function test_country_discovery_error_allows_fastest_only() {
            panel.snapshot = {vpnReady: true, vpnStatus: "disconnected", vpnCountriesError: "Could not load countries"};
            verify(findChild(panel, "vpn-connect").enabled);
            verify(findChild(panel, "vpn-countries-error").visible);
            search("Spain");
            verify(!findChild(panel, "vpn-connect").enabled);
            compare(findChild(panel, "search-results").count, 0);
        }
        function test_busy_and_hidden_panel_close_dropdown() {
            search("sw");
            panel.busy = true;
            tryCompare(findChild(panel, "search-popup"), "opened", false);
            verify(!findChild(panel, "vpn-country").enabled);
            panel.busy = false; search("sp");
            panel.visible = false;
            tryCompare(findChild(panel, "search-popup"), "opened", false);
            panel.visible = true;
        }
        function test_disconnect_and_server_details() {
            panel.snapshot = {vpnReady: true, vpnConnected: true, vpnStatus: "connected", vpnServer: "ES#1 in Madrid", vpnProtocol: "wireguard"};
            wait(10); verify(!findChild(panel, "vpn-country").visible);
            verify(findChild(panel, "vpn-server").text.includes("ES#1"));
            mouseClick(findChild(panel, "vpn-connect")); compare(Array.from(request.signalArguments[0]), ["disconnect", null]);
        }
        function test_signin_setup_and_unknown_states() {
            for (const status of ["signin", "install", "network", "unknown"]) {
                panel.snapshot = {vpnStatus: status, vpnError: "Setup detail"}; wait(10);
                verify(!findChild(panel, "vpn-connect").visible);
                compare(findChild(panel, "vpn-signin").visible, status === "signin");
                compare(findChild(panel, "vpn-setup").visible, ["install", "network"].includes(status));
                compare(findChild(panel, "vpn-error").text, "Setup detail");
            }
            panel.snapshot = {vpnStatus: "signin"}; wait(10);
            mouseClick(findChild(panel, "vpn-signin")); compare(signin.count, 1);
            mouseClick(findChild(panel, "vpn-refresh")); compare(refresh.count, 1);
            compare(request.count, 0);
        }
        function test_error_and_busy_feedback() {
            panel.busy = true; panel.operation = "disconnect"; wait(10);
            compare(findChild(panel, "vpn-status").text, "Disconnecting…");
            verify(!findChild(panel, "vpn-refresh").enabled);
            panel.busy = false; panel.error = "Connection failed";
            compare(findChild(panel, "vpn-error").text, "Connection failed");
        }
        function tailscaleState(connected) {
            return {vpnProvider: "tailscale", vpnProviderName: "Tailscale", vpnLocationKind: "exit-node",
                vpnProviders: [{id: "proton", name: "Proton VPN"}, {id: "tailscale", name: "Tailscale"}],
                vpnReady: true, vpnConnected: connected, vpnStatus: connected ? "connected" : "disconnected",
                vpnLocation: connected ? "100.64.0.2" : "", vpnServer: connected ? "paris.test.ts.net" : "Tailnet only",
                vpnLocations: [{id: "100.64.0.2", name: "paris.test.ts.net"}, {id: "100.64.0.3", name: "madrid.test.ts.net"}],
                vpnAddress: "100.64.0.1", vpnNetwork: "test.example"};
        }
        function test_provider_selection_is_separate_from_connect_or_disconnect() {
            panel.snapshot = Object.assign({}, panel.snapshot, {vpnProvider: "proton", vpnProviders: [
                {id: "proton", name: "Proton VPN"}, {id: "tailscale", name: "Tailscale"}]});
            const selector = findChild(panel, "vpn-provider");
            compare(selector.count, 2);
            selector.currentIndex = 1; selector.activated(1);
            compare(provider.count, 1); compare(provider.signalArguments[0][0], "tailscale");
            compare(request.count, 0);
            panel.busy = true; verify(!selector.enabled);
        }
        function test_tailscale_connects_tailnet_or_selected_exit_node() {
            panel.snapshot = tailscaleState(false); wait(10);
            const exitNode = findChild(panel, "vpn-exit-node");
            verify(exitNode.visible); compare(exitNode.value, "");
            mouseClick(findChild(panel, "vpn-connect")); compare(Array.from(request.signalArguments[0]), ["connect", ""]);
            exitNode.text = "paris.test.ts.net";
            mouseClick(findChild(panel, "vpn-connect")); compare(Array.from(request.signalArguments[1]), ["connect", "100.64.0.2"]);
            verify(findChild(panel, "vpn-status").text.includes("Disconnected"));
        }
        function test_tailscale_can_change_exit_node_while_connected() {
            panel.snapshot = tailscaleState(true); wait(10);
            const exitNode = findChild(panel, "vpn-exit-node");
            compare(exitNode.value, "100.64.0.2");
            const apply = findChild(panel, "vpn-apply-location");
            verify(!apply.enabled);
            exitNode.text = "madrid.test.ts.net"; verify(apply.enabled);
            mouseClick(apply); compare(Array.from(request.signalArguments[0]), ["set-location", "100.64.0.3"]);
            exitNode.text = ""; mouseClick(apply); compare(Array.from(request.signalArguments[1]), ["set-location", ""]);
            mouseClick(findChild(panel, "vpn-connect")); compare(Array.from(request.signalArguments[2]), ["disconnect", null]);
            verify(findChild(panel, "vpn-address").text.includes("100.64.0.1"));
        }
        function test_provider_switch_clears_incompatible_location_selection() {
            findChild(panel, "vpn-country").text = "Spain";
            panel.snapshot = tailscaleState(false); wait(10);
            compare(findChild(panel, "vpn-exit-node").text, "");
            const longName = "a".repeat(63) + ".example-tailnet.ts.net";
            panel.snapshot = Object.assign({}, panel.snapshot, {vpnLocations: [{id: "100.64.0.2", name: longName}]});
            findChild(panel, "vpn-exit-node").text = longName;
            compare(findChild(panel, "vpn-exit-node").value, "100.64.0.2");
            panel.snapshot = {vpnProvider: "proton", vpnReady: true, vpnStatus: "disconnected", vpnLocations: [{id: "ES", name: "Spain"}]};
            wait(10); compare(findChild(panel, "vpn-country").text, "");
            compare(request.count, 0);
        }
        function test_tailscale_service_authentication_and_approval_states() {
            for (const status of ["service", "signin", "approval", "unknown"]) {
                panel.snapshot = Object.assign(tailscaleState(false), {vpnReady: false, vpnStatus: status}); wait(10);
                verify(!findChild(panel, "vpn-connect").visible);
                compare(findChild(panel, "vpn-signin").visible, status === "signin");
                compare(findChild(panel, "vpn-setup").visible, ["service", "approval"].includes(status));
            }
        }
    }
}
