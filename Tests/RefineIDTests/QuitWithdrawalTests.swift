// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD && REFINEID_STREAM_TRANSPORT

  import Foundation
  import Testing

  @testable import RefineIDTestHost

  /// How long quitting waits for the withdrawal close (RAPP v26.10.29 §4.5
  /// item 8).
  ///
  /// Until it has left or the bound has passed, whichever comes first, and
  /// the quit is answered once. A click off still forgetting is waited for
  /// first, until its pairings are destroyed (§4.6 item 6).
  @Suite
  @MainActor
  internal struct QuitWithdrawalTests {
    private enum Fixture {
      /// A bound no test reaches.
      static let longBound: Duration = .seconds(30)
      /// A bound a test reaches at once.
      static let shortBound: Duration = .milliseconds(20)
      /// How long a close that never leaves takes.
      static let stuckClose: Duration = .seconds(30)
      /// How long a forgetting takes to destroy its pairings.
      static let destruction: Duration = .milliseconds(60)
      static let poll: Duration = .milliseconds(10)
      static let patience = 100
    }

    /// How often the quit was answered.
    @MainActor
    private final class Answers {
      var count = 0
    }

    /// Whether the pairings were destroyed.
    private final class Destroyed: @unchecked Sendable {
      private let lock = NSLock()
      private var value = false

      var isDone: Bool {
        lock.withLock { value }
      }

      func done() {
        lock.withLock { value = true }
      }
    }

    /// What a quit waits on: only `closes`.
    private static func closing(_ closes: Task<Bool, Never>) -> QuitWithdrawal.Pending {
      QuitWithdrawal.Pending(forgetting: nil, closes: closes)
    }

    private static func wait(until condition: () -> Bool) async throws {
      for _ in 0..<Fixture.patience where !condition() {
        try await Task.sleep(for: Fixture.poll)
      }
    }

    @Test("A close that left answers the quit before the bound")
    internal func closeLeftAnswersAtOnce() async throws {
      let answers = Answers()
      let closes = Task { true }
      QuitWithdrawal.wait(for: Self.closing(closes), atMost: Fixture.longBound) {
        answers.count += 1
      }
      try await Self.wait { answers.count == 1 }
      #expect(answers.count == 1)
    }

    @Test("A close that never leaves answers the quit at the bound")
    internal func stuckCloseAnswersAtTheBound() async throws {
      let answers = Answers()
      let closes = Task {
        try? await Task.sleep(for: Fixture.stuckClose)
        return false
      }
      defer { closes.cancel() }
      QuitWithdrawal.wait(for: Self.closing(closes), atMost: Fixture.shortBound) {
        answers.count += 1
      }
      try await Self.wait { answers.count == 1 }
      #expect(answers.count == 1)
    }

    @Test("The quit is answered once, though both the close and the bound arrive")
    internal func answeredOnce() async throws {
      let answers = Answers()
      let closes = Task { true }
      QuitWithdrawal.wait(for: Self.closing(closes), atMost: Fixture.shortBound) {
        answers.count += 1
      }
      try await Task.sleep(for: Fixture.shortBound * 2)
      try await Self.wait { answers.count == 1 }
      #expect(answers.count == 1)
    }

    @Test("A quit during a click off is answered only once its pairings are destroyed")
    internal func forgettingIsWaitedFor() async throws {
      let answers = Answers()
      let destroyed = Destroyed()
      let forgetting = Task.detached {
        try? await Task.sleep(for: Fixture.destruction)
        destroyed.done()
        return RemoteUseForgetting.Outcome()
      }
      QuitWithdrawal.wait(
        for: QuitWithdrawal.Pending(forgetting: forgetting, closes: Task { true }),
        atMost: Fixture.shortBound
      ) {
        #expect(destroyed.isDone, "the quit waited for the destruction")
        answers.count += 1
      }
      try await Self.wait { answers.count == 1 }
      #expect(answers.count == 1)
      #expect(destroyed.isDone)
    }
  }

#endif
