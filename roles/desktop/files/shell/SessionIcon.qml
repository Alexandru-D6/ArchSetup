import QtQuick
import QtQuick.Shapes

Item {
    id: icon
    required property string name
    property color color: "#e6e1e1"
    implicitWidth: 36
    implicitHeight: 36

    // Original outlines in a shared 24 x 24 coordinate space.
    readonly property var paths: ({
        "lock": "M7 10V7a5 5 0 0 1 10 0v3 M5 10h14v12H5Z M12 15v3",
        "suspend": "M20 14A9 9 0 0 1 10 3a9 9 0 1 0 10 11Z",
        "logout": "M10 3H4v18h6 M9 12h12 M17 8l4 4-4 4",
        "task-manager": "M3 3h18v15H3Z M6 12h3l2-5 3 7 2-4h3 M1 22h22",
        "firmware-setup": "M6 6h12v12H6Z M10 10h4v4h-4Z M9 2v4 M15 2v4 M9 18v4 M15 18v4 M2 9h4 M2 15h4 M18 9h4 M18 15h4",
        "poweroff": "M12 2v10 M6 5a9 9 0 1 0 12 0",
        "reboot": "M9 2 5 6l4 4 M5 6h7a8 8 0 1 1-7 7",
        "settings": "M3 3h18v18H3Z M12 8a4 4 0 1 0 0 8 4 4 0 1 0 0-8 M12 6v2 M12 16v2 M6 12h2 M16 12h2 M8 8l1.2 1.2 M14.8 14.8 16 16 M8 16l1.2-1.2 M14.8 9.2 16 8"
    })

    Shape {
        width: 24
        height: 24
        anchors.centerIn: parent
        scale: Math.min(icon.width, icon.height) / 24
        ShapePath {
            strokeColor: icon.color
            strokeWidth: 1.7
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: icon.paths[icon.name] || "" }
        }
    }
}
