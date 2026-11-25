// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import AppKit
  import CardCore
  import Foundation
  import notify

  /// Receives Web eID requests written by `RefineIDSafariExtension` into the
  /// shared App Group bridge, runs one interactive native macOS alert ceremony
  /// at a time, and delivers the signed response or error back to Safari.
  @MainActor
  internal final class WebEidCoordinator {
    // MARK: Nested Types

    private enum Constants {
      static let uninitializedToken: Int32 = -1
      static let fallbackPollIntervalMilliseconds = 500
    }

    // MARK: Static Properties

    internal static let shared = WebEidCoordinator()

    // MARK: Properties

    internal var activeCancelled = false

    private let store = WebEidBridgeStore.shared
    private var notificationToken: Int32 = Constants.uninitializedToken
    private var activeNonce: UUID?
    private var activeTask: Task<Void, Never>?
    private var fallbackPollTask: Task<Void, Never>?
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
      let status = notify_register_dispatch(
        WebEidValues.requestNotification,
        &notificationToken,
        DispatchQueue.main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.drainPendingRequests()
        }
      }
      if status == NOTIFY_STATUS_OK {
        started = true
      } else {
        startFallbackPolling()
      }
      drainPendingRequests()
    }

    /// Cancels any active Web eID ceremony immediately (for example on app quit)
    /// so Safari receives `ERR_WEBEID_USER_CANCELLED` rather than hanging.
    internal func cancelActiveRequest() {
      guard activeNonce != nil else { return }
      activeCancelled = true
      NSApp.abortModal()
    }

    internal func deliver(_ response: WebEidBridgeResponse, expiresAt: Date) {
      guard Date() < expiresAt else { return }
      _ = store.writeResponse(response)
      notify_post(WebEidValues.responseNotification)
    }

    private func startFallbackPolling() {
      guard fallbackPollTask == nil else { return }
      started = true
      fallbackPollTask = Task { [weak self] in
        while !Task.isCancelled {
          try? await Task.sleep(for: .milliseconds(Constants.fallbackPollIntervalMilliseconds))
          guard !Task.isCancelled, let self else { break }
          drainPendingRequests()
        }
      }
    }

    private func drainPendingRequests() {
      while let request = store.takeOldestPendingRequest() {
        handle(request)
      }
    }

    private func handle(_ request: WebEidBridgeRequest) {
      guard request.expiresAt > Date() else { return }
      if case .status = request.command {
        deliver(
          WebEidBridgeResponse(
            nonce: request.nonce,
            payload: .status(version: WebEidValues.compatibleProtocolVersion)
          ),
          expiresAt: request.expiresAt
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
          ),
          expiresAt: request.expiresAt
        )
        return
      }
      beginCeremony(for: request)
    }

    private func beginCeremony(for request: WebEidBridgeRequest) {
      activeNonce = request.nonce
      activeCancelled = false
      activeTask = Task { [weak self] in
        guard let self else { return }
        let result = await runCeremony(for: request)
        finishActiveRequest(nonce: request.nonce, expiresAt: request.expiresAt, result: result)
      }
    }

    private func finishActiveRequest(
      nonce: UUID,
      expiresAt: Date,
      result: Result<WebEidResponsePayload, WebEidError>
    ) {
      guard activeNonce == nonce else { return }
      activeNonce = nil
      activeCancelled = false
      activeTask = nil
      let response: WebEidBridgeResponse =
        switch result {
        case .success(let payload):
          WebEidBridgeResponse(nonce: nonce, payload: payload)

        case .failure(let error):
          WebEidBridgeResponse(nonce: nonce, error: error)
        }
      deliver(response, expiresAt: expiresAt)
      drainPendingRequests()
    }
  }

#endif
