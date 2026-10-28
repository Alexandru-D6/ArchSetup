import QtQuick
import QtTest
import "../../../roles/desktop/files/shell"

Item {
    width: 420; height: 760
    QtObject {
        id: theme
        property string uiFont: "DejaVu Sans"
        property color raised: "#ffe7eb"
        property color textColor: "#3d2c32"
        property color accent: "#bd0056"
        property color accentText: "white"
    }
    ProtonPanel { id: panel; width: parent.width; theme: theme }
    SignalSpy { id: request; target: panel; signalName: "controlRequested" }
    SignalSpy { id: signin; target: panel; signalName: "signinRequested" }
    SignalSpy { id: refresh; target: panel; signalName: "refreshRequested" }
    TestCase {
        name: "ProtonPanel"; when: windowShown
        function init() {
            panel.snapshot = {vpnReady: true, vpnConnected: false, vpnStatus: "disconnected"};
            panel.busy = false; panel.error = ""; panel.operation = "";
            findChild(panel, "vpn-country").text = "";
            request.clear(); signin.clear(); refresh.clear(); wait(10);
        }
        function test_fastest_and_country_connections() {
            const button = findChild(panel, "vpn-connect");
            mouseClick(button); compare(Array.from(request.signalArguments[0]), ["connect", ""]);
            findChild(panel, "vpn-country").text = "United States";
            mouseClick(button); compare(Array.from(request.signalArguments[1]), ["connect", "United States"]);
            findChild(panel, "vpn-country").text = "--random"; verify(!button.enabled);
            panel.busy = true; findChild(panel, "vpn-country").text = "ES"; verify(!button.enabled);
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
    }
}
