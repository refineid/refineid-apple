// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Foundation
  import notify

  /// Receives Web eID requests written by `RefineIDSafariExtension` into the
  /// shared App Group bridge, presents one interactive prompt at a time, and
  /// delivers the signed response or error back to Safari.
  @MainActor
  internal final class WebEidCoordinator {
    // MARK: Nested Types

    private enum Constants {
      static let uninitializedToken: Int32 = -1
    }

    // MARK: Static Properties

    internal static let shared = WebEidCoordinator()

    // MARK: Properties

    private let store = WebEidBridgeStore.shared
    private var notificationToken: Int32 = Constants.uninitializedToken
    private var activeNonce: UUID?
    private var activeModel: WebEidPromptModel?
    private var activeWindow: WebEidPromptWindow?
    private var timeoutTask: Task<Void, Never>?
    private var started = false

    // MARK: Lifecycle

    private init() {
      // Singleton coordinator.
    }

    // MARK: Functions

    /// Registers the Darwin notification listener and drains any request
    /// waiting from a cold launch triggered by Safari.
    internal func start() {
      guard !started, !RefineIDApp.hostsUnitTests else { return }
      started = true
      _ = notify_register_dispatch(
        WebEidValues.requestNotification,
        &notificationToken,
        DispatchQueue.main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.drainPendingRequests()
        }
      }
      drainPendingRequests()
    }

    /// Cancels any active Web eID prompt immediately (for example on app quit)
    /// so Safari receives `ERR_WEBEID_USER_CANCELLED` rather than hanging.
    internal func cancelActiveRequest() {
      activeModel?.cancel()
    }

    private func drainPendingRequests() {
      while let request = store.takeOldestPendingRequest() {
        handle(request)
      }
    }

    private func handle(_ request: WebEidBridgeRequest) {
      if case .status = request.command {
        deliver(
          WebEidBridgeResponse(
            nonce: request.nonce,
            payload: .status(version: WebEidValues.compatibleProtocolVersion)
          )
        )
        return
      }
      guard activeNonce == nil else {
        deliver(
          WebEidBridgeResponse(
            nonce: request.nonce,
            error: WebEidError(
              code: .actionPending,
              message: "Another Web eID request is already in progress"
            )
          )
        )
        return
      }
      presentPrompt(for: request)
    }

    private func presentPrompt(for request: WebEidBridgeRequest) {
      activeNonce = request.nonce
      let model = WebEidPromptModel(command: request.command) { [weak self] result in
        self?.finishActiveRequest(nonce: request.nonce, result: result)
      }
      let window = WebEidPromptWindow(model: model)
      activeModel = model
      activeWindow = window
      timeoutTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(WebEidValues.defaultUserInteractionTimeoutSeconds))
        guard !Task.isCancelled else { return }
        self?.activeModel?.expireTimeout()
      }
      window.present()
    }

    private func finishActiveRequest(
      nonce: UUID,
      result: Result<WebEidResponsePayload, WebEidError>
    ) {
      guard activeNonce == nonce else { return }
      timeoutTask?.cancel()
      timeoutTask = nil
      activeWindow?.closeProgrammatically()
      activeWindow = nil
      activeModel = nil
      activeNonce = nil
      let response: WebEidBridgeResponse =
        switch result {
        case .success(let payload):
          WebEidBridgeResponse(nonce: nonce, payload: payload)

        case .failure(let error):
          WebEidBridgeResponse(nonce: nonce, error: error)
        }
      deliver(response)
      drainPendingRequests()
    }

    private func deliver(_ response: WebEidBridgeResponse) {
      _ = store.writeResponse(response)
      notify_post(WebEidValues.responseNotification)
    }
  }

#endif
