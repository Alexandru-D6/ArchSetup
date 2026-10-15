pragma ComponentBehavior: Bound
import QtQml

QtObject {
    id: store
    property var applied: ({})
    property var draft: ({})
    property var latest: null
    property string revision: ""
    property string selectedCategory: "general"
    property bool loaded: false
    property bool busy: false
    property bool conflict: false
    property string error: ""
    property string sourceError: ""
    property string notice: ""
    property var fieldErrors: ({})
    property var catalog: ({timezones: [], layouts: [], maxLayouts: 4})
    property string catalogError: ""
    property var clockPreview: ({})
    property string previewError: ""
    property var runtime: ({})
    property bool recoveryNeeded: false
    readonly property var dirtyFields: Object.keys(draft).filter(key => JSON.stringify(draft[key]) !== JSON.stringify(applied[key]))
    readonly property bool dirty: dirtyFields.length > 0
    readonly property bool valid: Object.keys(fieldErrors).length === 0
    readonly property bool canApply: loaded && dirty && valid && !busy && !conflict && !sourceError && !recoveryNeeded
    signal applyRequested(var request)
    signal appliedSuccessfully()
    signal previewRequested(string zone)
    function clone(value) { return JSON.parse(JSON.stringify(value)); }
    function validLayouts(value) {
        return Array.isArray(value) && value.length >= 1 && value.length <= catalog.maxLayouts && value.every((item, index) =>
            item && catalog.layouts.some(layout => layout.id === item.layout && layout.variants.some(variant => variant.id === item.variant)) &&
            value.findIndex(pair => pair.layout === item.layout && pair.variant === item.variant) === index);
    }

    function adopt(snapshot) {
        revision = snapshot.revision;
        applied = clone(snapshot.values);
        draft = clone(snapshot.values);
        runtime = snapshot.runtime || ({});
        loaded = true;
        conflict = false;
        error = "";
        notice = "";
        fieldErrors = ({});
        requestPreview();
    }
    function receive(snapshot) {
        if (!snapshot) return;
        latest = snapshot;
        runtime = snapshot.runtime || ({});
        sourceError = "";
        if (loaded && snapshot.revision === revision) return;
        if (loaded && (dirty || busy)) {
            if (snapshot.revision !== revision) conflict = true;
        } else adopt(snapshot);
    }
    function edit(id, value) {
        if (!loaded || busy) return;
        // Older Qt versions wrap signal arguments as QVariantList/Map. Keep
        // drafts as plain JSON values so validation and dirty checks agree.
        if (value !== undefined) value = clone(value);
        draft = Object.assign({}, draft, {[id]: value});
        const errors = Object.assign({}, fieldErrors);
        if (id === "general.lockPowerRequiresAuth" && typeof value !== "boolean") errors[id] = "Choose enabled or disabled.";
        else if (id === "general.timezone" && (!value || !catalog.timezones.some(item => item.id === value))) errors[id] = "Choose an installed timezone.";
        else if (id.indexOf("general.clockPlacement.") === 0 && value !== null && (!value || ![value.x, value.y].every(number => typeof number === "number" && isFinite(number) && number >= 0 && number <= 1))) errors[id] = "Choose a position between 0% and 100%.";
        else if (id === "general.keyboard.layouts" && !validLayouts(value)) errors[id] = "Choose one to four installed, unique layout/variant pairs.";
        else delete errors[id];
        fieldErrors = errors;
        error = "";
        notice = "";
        if (id === "general.timezone") requestPreview();
    }
    function requestPreview() {
        const zone = draft["general.timezone"];
        if (typeof zone === "string" && zone.length) previewRequested(zone);
    }
    function recover() {
        if (busy) return;
        busy = true;
        error = "";
        applyRequested({operation: "recover"});
    }
    function revert() {
        if (busy || !latest) return;
        adopt(latest);
    }
    function apply() {
        if (!canApply) return false;
        const changes = {};
        for (const key of dirtyFields) changes[key] = draft[key];
        busy = true;
        error = "";
        notice = "";
        applyRequested({operation: "apply", revision: revision, changes: changes});
        return true;
    }
    function finish(response, operation = "apply") {
        busy = false;
        if (response.ok && response.snapshot) {
            const retained = clone(draft);
            latest = response.snapshot;
            adopt(response.snapshot);
            sourceError = "";
            recoveryNeeded = false;
            if (operation === "recover") {
                if (Object.keys(retained).length) draft = retained;
                notice = "Recovery complete. Review your changes.";
            } else {
                notice = "Changes applied";
                appliedSuccessfully();
            }
        } else {
            if (response.snapshot) latest = response.snapshot;
            conflict = response.code === "conflict";
            error = response.message || "Unable to apply settings. Try again.";
            fieldErrors = response.fields || ({});
            recoveryNeeded = response.code === "recovery";
        }
    }
}
