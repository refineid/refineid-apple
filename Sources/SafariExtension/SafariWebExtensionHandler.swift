// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import AppKit
  import CardCore
  import Foundation
  import notify
  import os
  import SafariServices

  /// Native messaging handler for the RefineID Safari Web Extension.
  ///
  /// Answers `status` immediately with the Web eID v2.x compatible version and
  /// bridges interactive card commands (`authenticate`, `get-signing-certificate`,
  /// `sign`) to the containing `RefineID.app` over the shared App Group container.
  internal final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private static let logger = Logger(
      subsystem: "fi.refineid.ReFineID",
      category: "safari-web-eid"
    )
    private static let pollIntervalMilliseconds = 150
    private static let containingAppAncestorDepth = 3

    private let bridgeQueue = DispatchQueue(label: "fi.refineid.webeid.safari-bridge")
    private var activeWaits: [UUID: WebEidBridgeWaitCoordinator] = [:]

    private static func containingAppURL() -> URL? {
      var candidate = Bundle.main.bundleURL
      for _ in 0..<Self.containingAppAncestorDepth {
        candidate.deleteLastPathComponent()
      }
      guard candidate.pathExtension == "app" else { return nil }
      return candidate
    }

    private static func clampedTimeout(from message: [String: Any]) -> TimeInterval {
      guard
        let milliseconds = message["timeout"] as? Double,
        milliseconds.isFinite,
        milliseconds > 0
      else {
        return WebEidValues.defaultUserInteractionTimeoutSeconds
      }
      let seconds = milliseconds / WebEidValues.millisecondsPerSecond
      return min(
        max(seconds, WebEidValues.minimumBridgeTimeoutSeconds),
        WebEidValues.maximumBridgeTimeoutSeconds
      )
    }

    internal func beginRequest(with context: NSExtensionContext) {
      let item = context.inputItems.first as? NSExtensionItem
      guard let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any] else {
        complete(
          context,
          dictionary: WebEidError(
            code: .nativeInvalidArgument,
            message: "Missing Web eID native message payload"
          ).responseDictionary()
        )
        return
      }

      let command: WebEidCommand
      do {
        command = try WebEidCommand.parse(dictionary: message)
      } catch let error as WebEidError {
        complete(context, dictionary: error.responseDictionary())
        return
      } catch {
        complete(
          context,
          dictionary: WebEidError(
            code: .nativeInvalidArgument,
            message: "Invalid Web eID native request"
          ).responseDictionary()
        )
        return
      }

      if case .status = command {
        let payload = WebEidResponsePayload.status(
          version: WebEidValues.compatibleProtocolVersion
        )
        complete(context, dictionary: payload.toDictionary())
        return
      }

      let timeoutSeconds = Self.clampedTimeout(from: message)
      forwardToContainingApp(command: command, timeoutSeconds: timeoutSeconds, context: context)
    }

    private func forwardToContainingApp(
      command: WebEidCommand,
      timeoutSeconds: TimeInterval,
      context: NSExtensionContext
    ) {
      let store = WebEidBridgeStore.shared
      let nonce = UUID()
      let request = WebEidBridgeRequest(nonce: nonce, createdAt: Date(), command: command)
      guard store.writeRequest(request) else {
        Self.logger.error("web-eid: App Group container unavailable")
        complete(
          context,
          dictionary: WebEidError(
            code: .nativeFatal,
            message: "RefineID App Group container is unavailable"
          ).responseDictionary()
        )
        return
      }

      let coordinator = WebEidBridgeWaitCoordinator(
        nonce: nonce,
        store: store,
        queue: bridgeQueue,
        timeoutSeconds: timeoutSeconds,
        pollIntervalMilliseconds: Self.pollIntervalMilliseconds
      ) { [weak self] dictionary in
        self?.activeWaits.removeValue(forKey: nonce)
        self?.complete(context, dictionary: dictionary)
      }
      bridgeQueue.sync {
        activeWaits[nonce] = coordinator
      }
      coordinator.start()

      notify_post(WebEidValues.requestNotification)
      launchContainingApp()
    }

    private func launchContainingApp() {
      guard let appURL = Self.containingAppURL() else {
        Self.logger.error("web-eid: containing RefineID.app URL could not be resolved")
        return
      }
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
        if let error {
          Self.logger.error(
            "web-eid: failed to launch containing app: \(error.localizedDescription, privacy: .public)"
          )
        }
      }
    }

    private func complete(_ context: NSExtensionContext, dictionary: [String: Any]) {
      let response = NSExtensionItem()
      response.userInfo = [SFExtensionMessageKey: dictionary]
      context.completeRequest(returningItems: [response], completionHandler: nil)
    }
  }

#endif
