pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: tools
    required property var desktop
    spacing: 10
    GridLayout {
        columns: 2
        Layout.fillWidth: true
        Repeater {
            model: [
                {label: "Clipboard", action: "clipboard"}, {label: "Emoji", action: "emoji"},
                {label: "Calculator", action: "calculator"}, {label: "Read screen text", action: "ocr"},
                {label: "Screen snip", action: "screenshot"}, {label: "Save screenshot", action: "screenshot-save"},
                {label: "Record region", action: "record-region"}, {label: "Record screen", action: "record-full"},
                {label: "Record with audio", action: "record-full-audio"}, {label: "Stop recording", action: "record-stop"},
                {label: "Code editor", action: "code-editor"}, {label: "Text editor", action: "text-editor"},
                {label: "Office", action: "office"}, {label: "Task manager", action: "task-manager"},
                {label: "Wallpaper", action: "wallpaper"}, {label: "Light / dark", action: "theme"}
            ]
            Button {
                id: button
                required property var modelData
                text: modelData.label
                Layout.fillWidth: true
                implicitHeight: 34
                onClicked: tools.desktop.utility(modelData.action)
                background: Rectangle { radius: 17; color: button.hovered ? tools.desktop.accent : tools.desktop.raised }
                contentItem: Text { text: button.text; color: button.hovered ? tools.desktop.surface : tools.desktop.ink; font.family: tools.desktop.uiFont; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            }
        }
    }
    Button {
        id: detach
        text: tools.desktop.toolsDetached ? "Close utilities" : "Detach utilities"
        Layout.fillWidth: true
        implicitHeight: 34
        onClicked: tools.desktop.control("detach-tools")
        background: Rectangle { radius: 17; color: tools.desktop.raised }
        contentItem: Text { text: detach.text; color: tools.desktop.ink; font.family: tools.desktop.uiFont; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
    }
    Item { Layout.fillHeight: true }
}
