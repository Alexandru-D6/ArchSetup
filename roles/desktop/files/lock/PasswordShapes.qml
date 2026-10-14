pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: mask
    property int count: 0
    property real shapeSize: 16
    property real spacing: 4
    property color color: "#eae0f5"
    property var shapes: []
    implicitWidth: Math.max(0, shapes.length * (shapeSize + spacing) - spacing)
    implicitHeight: shapeSize

    // Shapes depend only on length and fresh randomness, never on the characters.
    // Retain existing shapes when editing; only newly entered characters get one.
    onCountChanged: {
        const next = shapes.slice(0, Math.max(0, count));
        while (next.length < count) next.push(Math.floor(Math.random() * 6));
        shapes = next;
    }

    Row {
        spacing: mask.spacing
        Repeater {
            model: mask.shapes
            Canvas {
                id: shape
                required property int modelData
                width: mask.shapeSize
                height: width
                onWidthChanged: requestPaint()
                Connections {
                    target: mask
                    function onColorChanged() { shape.requestPaint(); }
                }
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.scale(width / 20, height / 20);
                    ctx.fillStyle = mask.color;
                    ctx.beginPath();
                    if (modelData === 0) {
                        ctx.arc(10, 10, 9, 0, 2 * Math.PI);
                    } else if (modelData === 1) {
                        ctx.moveTo(10, 0); ctx.lineTo(20, 10);
                        ctx.lineTo(10, 20); ctx.lineTo(0, 10);
                    } else if (modelData === 2) {
                        ctx.moveTo(10, 1); ctx.lineTo(20, 19); ctx.lineTo(0, 19);
                    } else if (modelData === 3) {
                        for (let i = 0; i < 6; i++) {
                            const angle = i * Math.PI / 3;
                            ctx.lineTo(10 + 10 * Math.cos(angle), 10 + 10 * Math.sin(angle));
                        }
                    } else if (modelData === 4) {
                        // A soft four-petal clover, like the reference's flower.
                        ctx.moveTo(10, 3);
                        ctx.bezierCurveTo(1, -5, -5, 1, 3, 10);
                        ctx.bezierCurveTo(-5, 19, 1, 25, 10, 17);
                        ctx.bezierCurveTo(19, 25, 25, 19, 17, 10);
                        ctx.bezierCurveTo(25, 1, 19, -5, 10, 3);
                    } else {
                        for (let i = 0; i < 16; i++) {
                            const angle = i * Math.PI / 8;
                            const radius = i % 2 ? 6 : 10;
                            ctx.lineTo(10 + radius * Math.cos(angle), 10 + radius * Math.sin(angle));
                        }
                    }
                    ctx.closePath();
                    ctx.fill();
                }
            }
        }
    }
}
