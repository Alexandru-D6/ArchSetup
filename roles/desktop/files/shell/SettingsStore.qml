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
    readonly property var dirtyFields: Object.keys(draft).filter(key => draft[key] !== applied[key])
    readonly property bool dirty: dirtyFields.length > 0
    readonly property bool valid: Object.keys(fieldErrors).length === 0
    readonly property bool canApply: loaded && dirty && valid && !busy && !conflict && !sourceError
    signal applyRequested(var request)
    signal appliedSuccessfully()

    function adopt(snapshot) {
        revision = snapshot.revision;
        applied = Object.assign({}, snapshot.values);
        draft = Object.assign({}, snapshot.values);
        loaded = true;
        conflict = false;
        error = "";
        notice = "";
        fieldErrors = ({});
    }
    function receive(snapshot) {
        if (!snapshot) return;
        latest = snapshot;
        sourceError = "";
        if (loaded && snapshot.revision === revision) return;
        if (loaded && (dirty || busy)) {
            if (snapshot.revision !== revision) conflict = true;
        } else adopt(snapshot);
    }
    function edit(id, value) {
        if (!loaded || busy) return;
        draft = Object.assign({}, draft, {[id]: value});
        const errors = Object.assign({}, fieldErrors);
        if (id === "general.lockPowerRequiresAuth" && typeof value !== "boolean") errors[id] = "Choose enabled or disabled.";
        else delete errors[id];
        fieldErrors = errors;
        error = "";
        notice = "";
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
    function finish(response) {
        busy = false;
        if (response.ok && response.snapshot) {
            latest = response.snapshot;
            adopt(response.snapshot);
            notice = "Changes applied";
            appliedSuccessfully();
        } else {
            if (response.snapshot) latest = response.snapshot;
            conflict = response.code === "conflict";
            error = response.message || "Unable to apply settings. Try again.";
            fieldErrors = response.fields || ({});
        }
    }
}
