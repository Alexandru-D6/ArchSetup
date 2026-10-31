pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: popup
    required property var theme
    property var notification: null
    property string position: "top-right"
    property bool barVisible: true
    property bool bottomBar: false
    readonly property bool bottomEdge: position.indexOf("bottom-") === 0
    anchors {
        top: !popup.bottomEdge
        bottom: popup.bottomEdge
        left: popup.position.endsWith("-left")
        right: popup.position.endsWith("-right")
    }
    margins {
        top: popup.barVisible && !popup.bottomBar ? 48 : 8
        bottom: popup.barVisible && popup.bottomBar ? 48 : 8
        left: 8
        right: 8
    }
    implicitWidth: Math.min(380, (screen?.width || 400) - 16)
    implicitHeight: Math.min(card.implicitHeight, (screen?.height || 800) - 64)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "archsetup-notification"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: card.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        NotificationCard { id: card; width: parent.width; theme: popup.theme; notification: popup.notification; compact: true }
    }
}
