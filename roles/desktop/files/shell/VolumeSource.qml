pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: source
    property var audio: null
    signal volumeChanged(int percentage, bool muted)

    function change(amount) {
        if (!Number.isInteger(amount) || amount === 0 || Math.abs(amount) > 100
            || !audio || !Number.isFinite(audio.volume)) return false;
        audio.volume = Math.max(0, Math.min(1, audio.volume + amount / 100));
        // The native audio object updates its cached value immediately.
        volumeChanged(Math.round(audio.volume * 100), audio.muted);
        return true;
    }
}
