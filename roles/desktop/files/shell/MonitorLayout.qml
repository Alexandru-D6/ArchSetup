pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

Item {
    id: layout
    required property var monitors
    required property string selectedOutput
    required property var theme
    signal selected(string name)
    readonly property var rectangles: monitors.filter(item => item.x !== null && item.y !== null).map(item => {
        const size = item.mode.split("@")[0].split("x").map(Number);
        if (item.transform % 2) size.reverse();
        return {name: item.name, x: item.x, y: item.y, w: size[0] / item.scale, h: size[1] / item.scale};
    })
    readonly property real minimumX: Math.min(0, ...rectangles.map(item => item.x))
    readonly property real minimumY: Math.min(0, ...rectangles.map(item => item.y))
    readonly property real totalWidth: Math.max(1, ...rectangles.map(item => item.x + item.w)) - minimumX
    readonly property real totalHeight: Math.max(1, ...rectangles.map(item => item.y + item.h)) - minimumY
    readonly property real factor: Math.max(0, Math.min((width - 8) / totalWidth, (height - 8) / totalHeight))
    Repeater {
        model: layout.rectangles
        delegate: Button {
            id: monitor
            required property var modelData
            x: (layout.width - layout.totalWidth * layout.factor) / 2 + (modelData.x - layout.minimumX) * layout.factor
            y: (layout.height - layout.totalHeight * layout.factor) / 2 + (modelData.y - layout.minimumY) * layout.factor
            width: Math.max(1, modelData.w * layout.factor - 3)
            height: Math.max(1, modelData.h * layout.factor - 3)
            padding: 4
            text: modelData.name
            Accessible.name: "Select display " + text
            onClicked: layout.selected(modelData.name)
            background: Rectangle {
                radius: 6
                color: monitor.modelData.name === layout.selectedOutput ? layout.theme.accent : layout.theme.surface
                border.width: monitor.activeFocus ? 3 : 1
                border.color: layout.theme.accent
            }
            contentItem: Text {
                text: monitor.text
                color: monitor.modelData.name === layout.selectedOutput ? layout.theme.accentText : layout.theme.textColor
                font.family: layout.theme.uiFont
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
    }
}
