pragma ComponentBehavior: Bound
import QtQml

QtObject {
    id: registry
    property var categories: [
        {id: "general", title: "General", page: Qt.resolvedUrl("GeneralSettings.qml")}
    ]
    // Register settings only when their controls and backend are implemented.
    // Forms and search share the same IDs, labels, descriptions and aliases.
    property var settings: [
        {id: "general.lockPowerRequiresAuth", category: "general", section: "Lock-screen power",
            label: "Require unlock before shutdown or reboot",
            description: "Hide power controls on the lock screen. Unlock and use the desktop session menu to shut down or restart.",
            keywords: "power shutdown reboot restart login password authentication security lock"}
    ]
    function setting(id) { return settings.find(item => item.id === id); }
    function category(id) { return categories.find(item => item.id === id); }
    function normalize(value) { return value.toLowerCase().replace(/\s+/g, " ").trim(); }
    function search(query) {
        const terms = normalize(query).split(" ").filter(Boolean);
        if (!terms.length) return [];
        const result = [];
        for (const group of categories) {
            for (const item of settings.filter(item => item.category === group.id)) {
                const text = normalize([group.title, item.section, item.label, item.description, item.keywords].join(" "));
                if (terms.every(term => text.includes(term))) result.push(Object.assign({}, item, {categoryTitle: group.title}));
            }
        }
        return result;
    }
}
