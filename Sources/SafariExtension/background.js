// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

(() => {
  const EXTENSION_VERSION = "2.6.0";
  const NATIVE_APP_ID = "fi.refineid.ReFineID";
  const DEFAULT_TIMEOUT_MS = 120000;

  let activeOperation = false;

  function makeFailure(initialAction, code, message, extra) {
    return {
      action: `${initialAction}-failure`,
      error: Object.assign(
        {
          code: code || "ERR_WEBEID_UNKNOWN_ERROR",
          message: message || "Web eID operation failed",
        },
        extra || {}
      ),
    };
  }

  function extractHttpsOrigin(sender) {
    const rawUrl = (sender && sender.url) || (sender && sender.tab && sender.tab.url);
    if (!rawUrl) return null;
    try {
      const parsed = new URL(rawUrl);
      if (parsed.protocol !== "https:") return null;
      return parsed.origin;
    } catch (_error) {
      return null;
    }
  }

  function sendNative(payload) {
    return new Promise((resolve, reject) => {
      try {
        const result = browser.runtime.sendNativeMessage(NATIVE_APP_ID, payload, (reply) => {
          if (browser.runtime.lastError) {
            reject(new Error(browser.runtime.lastError.message));
          } else {
            resolve(reply);
          }
        });
        if (result && typeof result.then === "function") {
          result.then(resolve, reject);
        }
      } catch (error) {
        reject(error);
      }
    });
  }

  async function handleStatus(message) {
    const reply = await sendNative({ command: "status" });
    if (!reply || typeof reply.version !== "string") {
      return makeFailure(
        "web-eid:status",
        "ERR_WEBEID_NATIVE_UNAVAILABLE",
        "RefineID native helper did not answer status",
        { extension: EXTENSION_VERSION, library: message.libraryVersion }
      );
    }
    return {
      action: "web-eid:status-success",
      library: message.libraryVersion || EXTENSION_VERSION,
      extension: EXTENSION_VERSION,
      nativeApp: reply.version,
    };
  }

  async function handleInteractive(message, sender) {
    const action = message.action;
    const origin = extractHttpsOrigin(sender);
    if (!origin) {
      return makeFailure(
        action,
        "ERR_WEBEID_CONTEXT_INSECURE",
        "Web eID requires an HTTPS origin"
      );
    }

    if (activeOperation) {
      return makeFailure(
        action,
        "ERR_WEBEID_ACTION_PENDING",
        "Another Web eID operation is already in progress"
      );
    }

    const options = message.options || {};
    const timeout =
      typeof options.userInteractionTimeout === "number" && options.userInteractionTimeout > 0
        ? options.userInteractionTimeout
        : DEFAULT_TIMEOUT_MS;
    const lang = typeof options.lang === "string" && options.lang ? options.lang : undefined;

    let nativeRequest;
    if (action === "web-eid:authenticate") {
      nativeRequest = {
        command: "authenticate",
        timeout,
        arguments: Object.assign(
          { origin, challengeNonce: message.challengeNonce },
          lang ? { lang } : {}
        ),
      };
    } else if (action === "web-eid:get-signing-certificate") {
      nativeRequest = {
        command: "get-signing-certificate",
        timeout,
        arguments: Object.assign({ origin }, lang ? { lang } : {}),
      };
    } else if (action === "web-eid:sign") {
      nativeRequest = {
        command: "sign",
        timeout,
        arguments: Object.assign(
          {
            origin,
            certificate: message.certificate,
            hash: message.hash,
            hashFunction: message.hashFunction,
          },
          lang ? { lang } : {}
        ),
      };
    } else {
      return makeFailure(action, "ERR_WEBEID_NATIVE_INVALID_ARGUMENT", "Unsupported Web eID action");
    }

    activeOperation = true;
    try {
      const reply = await sendNative(nativeRequest);
      if (!reply || typeof reply !== "object") {
        return makeFailure(
          action,
          "ERR_WEBEID_NATIVE_UNAVAILABLE",
          "RefineID did not return a response"
        );
      }
      if (reply.error) {
        return makeFailure(action, reply.error.code, reply.error.message);
      }
      return Object.assign({ action: `${action}-success` }, reply);
    } catch (error) {
      return makeFailure(
        action,
        "ERR_WEBEID_NATIVE_FATAL",
        (error && error.message) || "Native Web eID communication failed"
      );
    } finally {
      activeOperation = false;
    }
  }

  browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (!message || typeof message.action !== "string") return false;

    const promise =
      message.action === "web-eid:status"
        ? handleStatus(message)
        : handleInteractive(message, sender);

    promise
      .then((response) => sendResponse(response))
      .catch((error) =>
        sendResponse(
          makeFailure(
            message.action,
            "ERR_WEBEID_UNKNOWN_ERROR",
            (error && error.message) || "Unexpected extension error"
          )
        )
      );

    return true;
  });
})();
