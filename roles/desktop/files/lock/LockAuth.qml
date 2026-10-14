pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Pam

QtObject {
    id: auth
    property bool busy: false
    property string message: ""
    property string prompt: "Enter password"
    property string pendingResponse: ""
    property bool hasPendingResponse: false
    readonly property alias context: pam
    signal succeeded()
    signal cleared()

    function submit(response) {
        if (busy) return;
        busy = true;
        message = "";
        cleared();
        if (pam.active && pam.responseRequired) pam.respond(response);
        else {
            pendingResponse = response;
            hasPendingResponse = true;
            if (!pam.start()) {
                pendingResponse = "";
                hasPendingResponse = false;
                busy = false;
                message = "Authentication unavailable. Try again.";
            }
        }
    }
    property PamContext pamContext: PamContext {
        id: pam
        config: "archsetup-hyprlock"
        onPamMessage: {
            if (!responseRequired) return;
            if (auth.hasPendingResponse && !responseVisible) {
                const response = auth.pendingResponse;
                auth.pendingResponse = "";
                auth.hasPendingResponse = false;
                respond(response);
            } else {
                auth.pendingResponse = "";
                auth.hasPendingResponse = false;
                auth.prompt = message || "Authentication response";
                auth.busy = false;
            }
        }
        onCompleted: result => {
            auth.pendingResponse = "";
            auth.hasPendingResponse = false;
            auth.cleared();
            if (result === PamResult.Success) auth.succeeded();
            else {
                auth.busy = false;
                auth.prompt = "Enter password";
                auth.message = "Authentication failed. Try again.";
            }
        }
    }
}
