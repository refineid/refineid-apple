// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

(() => {
  const WEBEID_PREFIX = "web-eid:";
  const RESPONSE_SUFFIXES = ["-ack", "-success", "-failure"];
  const INITIAL_ACTIONS = new Set([
    "web-eid:status",
    "web-eid:authenticate",
    "web-eid:get-signing-certificate",
    "web-eid:sign",
  ]);

  function isInitialWebEidMessage(event) {
    if (event.source !== window) return false;
    if (event.origin !== window.location.origin) return false;
    const action = event.data && event.data.action;
    if (typeof action !== "string" || !action.startsWith(WEBEID_PREFIX)) return false;
    if (action === "web-eid:warning") return false;
    if (RESPONSE_SUFFIXES.some((suffix) => action.endsWith(suffix))) return false;
    return INITIAL_ACTIONS.has(action);
  }

  // The handler returns unless isInitialWebEidMessage accepts the event,
  // which checks event.source, event.origin and the action allowlist.
  // nosemgrep: insufficient-postmessage-origin-validation
  window.addEventListener("message", async (event) => {
    if (!isInitialWebEidMessage(event)) return;

    const action = event.data.action;
    if (!window.isSecureContext) {
      window.postMessage(
        {
          action: `${action}-failure`,
          error: {
            code: "ERR_WEBEID_CONTEXT_INSECURE",
            message: "Web eID requires a secure HTTPS context",
          },
        },
        event.origin
      );
      return;
    }

    window.postMessage({ action: `${action}-ack` }, event.origin);

    try {
      const response = await browser.runtime.sendMessage(event.data);
      if (response) {
        window.postMessage(response, event.origin);
      }
    } catch (error) {
      window.postMessage(
        {
          action: `${action}-failure`,
          error: {
            code: "ERR_WEBEID_UNKNOWN_ERROR",
            message: (error && error.message) || "Extension bridge failed",
          },
        },
        event.origin
      );
    }
  });
})();
