// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore
  import CryptoTokenKit
  import Foundation
  import os

  /// Whether CryptoTokenKit has published the reader card's token, and the
  /// wait remote card work makes for it.
  ///
  /// The system asks the token extension for a reader card's token once per
  /// insertion, as the slot reports the card. The extension reads the card
  /// to answer. A session the app holds at that moment leaves the
  /// extension's command unanswered, and the card then has no token until
  /// it is reinserted. Remote card work therefore opens the reader card
  /// only once the token exists, or once the system has had its time to
  /// publish one.
  internal final class ReaderTokenPublication: @unchecked Sendable {
    // MARK: Static Properties

    internal static let shared = ReaderTokenPublication()

    /// How long after a reader card arrives remote card work waits for its
    /// token before opening the card anyway.
    internal static let publicationWaitSeconds: Int64 = 5

    // MARK: Properties

    private let watcher = TKTokenWatcher()

    /// When the wait for the present reader card's token runs out.
    private let deadline = OSAllocatedUnfairLock<ContinuousClock.Instant?>(initialState: nil)

    /// Waiters for the token, by key.
    private let waiters = OSAllocatedUnfairLock<[UUID: CheckedContinuation<Void, Never>]>(
      initialState: [:])

    /// Called whenever a card token is published.
    private let arrival = OSAllocatedUnfairLock<(@Sendable () -> Void)?>(initialState: nil)

    // MARK: Computed Properties

    /// Whether a card token is published now.
    internal var isPublished: Bool {
      watcher.tokenIDs.contains(where: Self.isCardToken)
    }

    // MARK: Lifecycle

    private init() {
      watcher.setInsertionHandler(Self.insertionHandler(for: self))
    }

    // MARK: Static Functions

    /// Whether a token identifier names a card token, rather than a
    /// remote-card identity configured under a card class.
    private static func isCardToken(_ tokenIdentifier: String) -> Bool {
      CardTokenNamespace.owns(tokenIdentifier: tokenIdentifier)
        && !CardTokenNamespace.isDisplacedRemoteCardToken(tokenIdentifier: tokenIdentifier)
    }

    /// Builds the ctkd callback outside any actor; `TKTokenWatcher`
    /// invokes it on its XPC queue.
    private static func insertionHandler(
      for publication: ReaderTokenPublication
    ) -> @Sendable (String) -> Void {
      { [weak publication] tokenIdentifier in
        guard isCardToken(tokenIdentifier) else { return }
        publication?.published()
      }
    }

    // MARK: Functions

    /// Calls `handler` whenever a card token is published.
    internal func onPublished(_ handler: @escaping @Sendable () -> Void) {
      arrival.withLock { $0 = handler }
    }

    /// A reader card arrived: its token is due within
    /// ``publicationWaitSeconds``.
    internal func readerCardArrived() {
      let due = ContinuousClock.now + .seconds(Self.publicationWaitSeconds)
      deadline.withLock { $0 = due }
    }

    /// The reader card left: no token is coming, so stop waiting for one
    /// and release anyone already waiting.
    internal func readerCardDeparted() {
      deadline.withLock { $0 = nil }
      resumeAllWaiters()
    }

    /// Returns once the card token is published or the wait for it has
    /// run out.
    internal func awaitPublication() async {
      guard !isPublished,
        let due = deadline.withLock({ $0 }),
        ContinuousClock.now < due
      else { return }
      let key = UUID()
      await withCheckedContinuation { continuation in
        waiters.withLock { $0[key] = continuation }
        if isPublished {
          resume(key)
          return
        }
        // Strong capture: the timeout must resume the continuation even
        // if nothing else references this (a singleton, so no cycle).
        Task { [self] in
          try? await Task.sleep(until: due, clock: .continuous)
          resume(key)
        }
      }
    }

    private func resume(_ key: UUID) {
      waiters.withLock { $0.removeValue(forKey: key) }?.resume()
    }

    /// Releases everyone waiting on the token, without the arrival note.
    private func resumeAllWaiters() {
      let pending = waiters.withLock { waiting in
        defer { waiting.removeAll() }
        return Array(waiting.values)
      }
      for continuation in pending {
        continuation.resume()
      }
    }

    private func published() {
      resumeAllWaiters()
      arrival.withLock { $0 }?()
    }
  }
#endif
