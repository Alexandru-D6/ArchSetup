pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: clock
    property var position: null
    property real safeLeft: 16
    property real safeRight: 16
    property real safeTop: 16
    property real safeBottom: 16
    property real defaultX: 70
    property real defaultY: parent.height - 300
    readonly property real maximumX: Math.max(safeLeft, parent.width - safeRight - width)
    readonly property real maximumY: Math.max(safeTop, parent.height - safeBottom - height)
    x: Math.round(Math.max(safeLeft, Math.min(maximumX, position ? safeLeft + position.x * (maximumX - safeLeft) : defaultX)))
    y: Math.round(Math.max(safeTop, Math.min(maximumY, position ? safeTop + position.y * (maximumY - safeTop) : defaultY)))
}
