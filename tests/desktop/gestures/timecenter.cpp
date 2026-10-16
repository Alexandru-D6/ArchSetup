// QtTest's QML mouseWheel helper only sends NoScrollPhase events. Exercise the
// real begin/update/end sequence here: an unconsumed neutral begin used to leave
// SwipeView's index updated while its contentX stayed on the previous page.
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTest>
#include <QWheelEvent>
#include <cmath>
#include <cstdio>
#include <stdexcept>
#include <utility>

static void require(bool condition, const char *message) {
    if (!condition) throw std::runtime_error(message);
}

int main(int argc, char **argv) {
    QGuiApplication app(argc, argv);
    qInstallMessageHandler([](QtMsgType, const QMessageLogContext &, const QString &message) {
        fprintf(stderr, "%s\n", qPrintable(message));
    });
    try {
        require(argc == 2, "Expected the QML fixture path");
        QQmlApplicationEngine engine(QUrl::fromLocalFile(argv[1]));
        auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().value(0));
        require(window, "Could not load the fixture");
        QTest::qWait(300);
        auto center = window->findChild<QQuickItem *>("time-center");
        auto pages = window->findChild<QQuickItem *>("time-pages");
        require(center && pages, "Missing time center or page slider");
        auto content = pages->property("contentItem").value<QQuickItem *>();
        require(content, "Missing page content");
        QPointingDevice touchpad("Regression touchpad", 42, QInputDevice::DeviceType::TouchPad,
            QPointingDevice::PointerType::Finger, QInputDevice::Capability::Position |
            QInputDevice::Capability::Scroll | QInputDevice::Capability::PixelScroll, 5, 0);
        auto wheel = [&](QPointF position, QPoint pixel, QPoint angle, Qt::ScrollPhase phase) {
            QWheelEvent event(position, window->mapToGlobal(position), pixel, angle,
                Qt::NoButton, Qt::NoModifier, phase, false, Qt::MouseEventNotSynthesized, &touchpad);
            QCoreApplication::sendEvent(window, &event);
            QTest::qWait(25);
        };
        auto checkPage = [&](int expected) {
            require(center->property("currentPage").toInt() == expected, "Wrong selected tab");
            require(QTest::qWaitFor([&] {
                return std::abs(content->property("contentX").toDouble() - expected * pages->width()) < 1;
            }, 1500), "Selected tab changed but the page content did not move");
            auto item = pages->property("currentItem").value<QQuickItem *>();
            require(item && std::abs(item->mapToItem(pages, QPointF()).x()) < 1, "Selected page is outside the viewport");
        };
        auto gesture = [&](QPointF position, QPoint pixel, QPoint angle) {
            wheel(position, {}, {}, Qt::ScrollBegin);
            for (int i = 0; i < 5; i++) wheel(position, pixel, angle, Qt::ScrollUpdate);
            wheel(position, {}, {}, Qt::ScrollEnd);
            QTest::qWait(350);
        };
        checkPage(0);
        gesture({300, 300}, {-12, 0}, {-24, 0});
        checkPage(1);
        gesture({250, 32}, {-12, 0}, {-24, 0});
        checkPage(2);
        gesture({300, 300}, {12, 0}, {24, 0});
        checkPage(1);

        // Long gestures can select another page while their finger is still
        // down. Both intermediate and final content positions must follow.
        wheel({300, 300}, {}, {}, Qt::ScrollBegin);
        wheel({300, 300}, {-12, 0}, {-24, 0}, Qt::ScrollUpdate);
        checkPage(2);
        wheel({300, 300}, {}, {}, Qt::ScrollEnd);
        checkPage(2);

        // Real vertical gestures can begin with a one-pixel sideways sample.
        // It must not lock the gesture horizontally or swallow the list's begin.
        for (const auto &[page, name] : {std::pair{1, "todo-list"}, {2, "world-clock-scroll"}, {4, "stopwatch-laps"}}) {
            center->setProperty("currentPage", page);
            QTest::qWait(350);
            auto view = window->findChild<QQuickItem *>(name);
            require(view, "Missing scrolling view");
            auto list = page == 2 ? view->property("contentItem").value<QQuickItem *>() : view;
            require(list, "Missing vertical list content");
            list->setProperty("contentY", 0);
            auto position = view->mapToScene({100, view->height() / 2});
            wheel(position, {}, {}, Qt::ScrollBegin);
            wheel(position, {-1, 0}, {-2, 0}, Qt::ScrollUpdate);
            for (int i = 0; i < 5; i++) wheel(position, {-1, -18}, {-2, -36}, Qt::ScrollUpdate);
            wheel(position, {}, {}, Qt::ScrollEnd);
            QTest::qWait(350);
            const auto down = list->property("contentY").toDouble();
            require(down > 30, "Vertical touchpad gesture with initial sideways jitter did not scroll the list");
            checkPage(page);
            gesture(position, {1, 18}, {2, 36});
            require(list->property("contentY").toDouble() < down - 5, "Reverse vertical gesture did not scroll back up");
            checkPage(page);
        }
        // The next horizontal gesture must still move the content after
        // interacting with a vertical list.
        gesture({300, 300}, {12, 0}, {24, 0});
        checkPage(3);
        fprintf(stdout, "ARCHSETUP_TIME_CENTER_GESTURES_PASSED\n");
        return 0;
    } catch (const std::exception &error) {
        fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}
