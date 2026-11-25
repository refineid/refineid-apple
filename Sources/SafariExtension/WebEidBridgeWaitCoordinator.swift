// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Foundation
  import notify

  /// Coordinates waiting for one bridged response via Darwin notification,
  /// short fallback polling, and a bounded user-interaction timeout.
  internal final class WebEidBridgeWaitCoordinator: @unchecked Sendable {
    private let nonce: UUID
    private let store: WebEidBridgeStore
    private let queue: DispatchQueue
    private let timeoutSeconds: TimeInterval
    private let pollIntervalMilliseconds: Int
    private let completion: ([String: Any]) -> Void

    private var notifyToken: Int32 = NOTIFY_TOKEN_INVALID
    private var pollTimer: DispatchSourceTimer?
    private var timeoutWork: DispatchWorkItem?
    private var finished = false

    internal init(
      nonce: UUID,
      store: WebEidBridgeStore,
      queue: DispatchQueue,
      timeoutSeconds: TimeInterval,
      pollIntervalMilliseconds: Int,
      completion: @escaping ([String: Any]) -> Void
    ) {
      self.nonce = nonce
      self.store = store
      self.queue = queue
      self.timeoutSeconds = timeoutSeconds
      self.pollIntervalMilliseconds = pollIntervalMilliseconds
      self.completion = completion
    }

    internal func start() {
      var token: Int32 = NOTIFY_TOKEN_INVALID
      notify_register_dispatch(WebEidValues.responseNotification, &token, queue) { [weak self] _ in
        self?.checkResponse()
      }
      notifyToken = token

      let timer = DispatchSource.makeTimerSource(queue: queue)
      timer.schedule(
        deadline: .now() + .milliseconds(pollIntervalMilliseconds),
        repeating: .milliseconds(pollIntervalMilliseconds)
      )
      timer.setEventHandler { [weak self] in
        self?.checkResponse()
      }
      timer.resume()
      pollTimer = timer

      let timeout = DispatchWorkItem { [weak self] in
        guard let self else { return }
        store.removeRequest(nonce: nonce)
        finish(
          with: WebEidError(
            code: .userTimeout,
            message: "Timed out waiting for user confirmation in RefineID"
          ).responseDictionary()
        )
      }
      timeoutWork = timeout
      queue.asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
    }

    private func checkResponse() {
      guard !finished, let response = store.takeResponse(nonce: nonce) else { return }
      finish(with: response.toExtensionDictionary())
    }

    private func finish(with dictionary: [String: Any]) {
      guard !finished else { return }
      finished = true
      timeoutWork?.cancel()
      timeoutWork = nil
      pollTimer?.cancel()
      pollTimer = nil
      if notifyToken != NOTIFY_TOKEN_INVALID {
        notify_cancel(notifyToken)
        notifyToken = NOTIFY_TOKEN_INVALID
      }
      completion(dictionary)
    }
  }

#endif
