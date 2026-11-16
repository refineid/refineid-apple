// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if FEATURE_SCS && os(macOS)
  import CardCore
  import Foundation
  import os

  /// Serial execution lane for stateful `POST /sign` requests, keeping
  /// `/version` and `OPTIONS` off the card and PIN queue.
  internal final class ScsSignExecutor: Sendable {
    private let signQueue = DispatchQueue(label: "fi.refineid.scs.sign")
    private let backend: any ScsSigningBackend & Sendable
    private let cardCancellationHook: (@Sendable (ScsPromptCancellationToken, () -> Data) -> Data)?
    private let resetBackendHook: @Sendable () -> Void
    private let transactions = ScsTransactionManager()
    private let busy = OSAllocatedUnfairLock(initialState: false)

    internal init(
      backend: any ScsSigningBackend & Sendable,
      cardCancellationHook: (@Sendable (ScsPromptCancellationToken, () -> Data) -> Data)?,
      resetBackendHook: @escaping @Sendable () -> Void
    ) {
      self.backend = backend
      self.cardCancellationHook = cardCancellationHook
      self.resetBackendHook = resetBackendHook
    }

    /// Runs a stateless fast-path request synchronously on the caller's
    /// queue.
    internal func dispatchFastPath(_ exchange: ScsHttpExchange) -> Data {
      ScsDispatcher.dispatch(
        request: exchange.request,
        body: exchange.body,
        backend: backend,
        transactions: transactions
      )
    }

    /// Clears pending transaction state and backend caches on server
    /// stop.
    internal func reset() {
      busy.withLock { $0 = false }
      transactions.clear()
      resetBackendHook()
    }

    /// Enqueues one `POST /sign` exchange when idle, or returns `false`
    /// immediately when another sign ceremony is already active.
    internal func submit(
      _ exchange: ScsHttpExchange,
      token: ScsPromptCancellationToken,
      timeoutSeconds: Double,
      callbackQueue: DispatchQueue,
      completion: @escaping @Sendable (Data?) -> Void
    ) -> Bool {
      let claimed = busy.withLock { isBusy -> Bool in
        guard !isBusy else { return false }
        isBusy = true
        return true
      }
      guard claimed else { return false }
      let completed = OSAllocatedUnfairLock(initialState: false)
      let claimCompletion: @Sendable () -> Bool = {
        completed.withLock { done in
          guard !done else { return false }
          done = true
          return true
        }
      }
      callbackQueue.asyncAfter(deadline: .now() + timeoutSeconds) {
        guard claimCompletion() else { return }
        token.cancel()
        completion(nil)
      }
      signQueue.async { [self] in
        defer { busy.withLock { $0 = false } }
        guard !token.isCancelled else {
          callbackQueue.async { if claimCompletion() { completion(nil) } }
          return
        }
        let compute = {
          ScsDispatcher.dispatch(
            request: exchange.request,
            body: exchange.body,
            backend: self.backend,
            transactions: self.transactions
          )
        }
        let response = cardCancellationHook.map { $0(token, compute) } ?? compute()
        callbackQueue.async {
          guard claimCompletion() else { return }
          completion(token.isCancelled ? nil : response)
        }
      }
      return true
    }
  }
#endif
