import QtQuick
import QtTest
import "../../../roles/desktop/files/shell"

Rectangle {
    id: fixture
    width: 420; height: 240
    color: "#fff8f9"
    QtObject {
        id: palette
        property color raised: "#ffe7eb"
        property color textColor: "#3d2c32"
        property color accent: "#bd0056"
        property color accentText: "#ffffff"
        property string uiFont: "DejaVu Sans"
    }
    NotificationCard { id: card; x: 16; y: 16; width: 388; theme: palette; compact: true; notification: null }
    TestCase {
        name: "NotificationCard"
        when: windowShown
        function test_severity_appearance_and_dismissal() {
            let dismissed = false;
            card.notification = {appName: "Battery", summary: "Battery low", body: "20% remaining. Connect your charger soon.",
                urgency: 1, actions: [], dismiss: () => { dismissed = true; }};
            compare(card.critical, false);
            compare(card.color, palette.raised);
            card.notification = {appName: "Battery", summary: "Battery critically low",
                body: "10% remaining. Connect your charger now. The computer will suspend below 3%.",
                urgency: 2, actions: [], dismiss: () => { dismissed = true; }};
            compare(card.critical, true);
            compare(card.color, palette.accent);
            compare(card.foreground, palette.accentText);
            waitForRendering(card);
            grabImage(fixture).save("/tmp/archsetup-battery-critical.png");
            const close = findChild(card, "notification-dismiss");
            verify(close !== null);
            mouseClick(close);
            compare(dismissed, true);
        }
    }
}
