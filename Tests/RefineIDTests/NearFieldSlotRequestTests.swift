// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RefineID

/// Asking for the near-field slot waits out a busy radio and the reader's
/// pause after a field, and gives up at once on any other refusal.
@Suite
internal struct NearFieldSlotRequestTests {
  /// Counts the attempts and the pauses of one request.
  private final class Attempts: @unchecked Sendable {
    private let lock = NSLock()
    private var made = 0
    private var waited: [Duration] = []

    var count: Int {
      lock.withLock { made }
    }

    var pauses: [Duration] {
      lock.withLock { waited }
    }

    func attempt() -> Int {
      lock.withLock {
        made += 1
        return made
      }
    }

    func pause(_ interval: Duration) {
      lock.withLock { waited.append(interval) }
    }
  }

  /// The slot a successful attempt gives.
  private static let slot = "slot"

  /// Attempts the reader's pause refuses before the slot is given.
  private static let pausedAttempts = 9

  /// What `nfcd` answers while the reader's pause runs.
  private static let readerPause = NSError(
    domain: NearFieldSlotRequest.readerPauseErrorDomain,
    code: NearFieldSlotRequest.readerPauseErrorCode)

  /// What the system answers while the radio is still held elsewhere.
  private static let busyRadio = NSError(
    domain: "radio", code: .zero,
    userInfo: [NSLocalizedDescriptionKey: "The NFC radio is busy"])

  /// A refusal that does not pass.
  private static let entitlementMissing = NSError(
    domain: "entitlement", code: .zero,
    userInfo: [NSLocalizedDescriptionKey: "Missing entitlement"])

  private static func request(
    _ attempts: Attempts,
    answer: (Int) -> Result<String, any Error>
  ) async -> Result<String, NearFieldSlotRequest.Refusal> {
    await NearFieldSlotRequest.request(
      attempt: { answer(attempts.attempt()) },
      pause: { interval in attempts.pause(interval) }
    )
  }

  @Test("The reader's pause after a field is waited out, one attempt a second")
  internal func readerPauseIsWaitedOut() async {
    let attempts = Attempts()
    let answer = await Self.request(attempts) { made in
      made > Self.pausedAttempts ? .success(Self.slot) : .failure(Self.readerPause)
    }
    #expect(answer == .success(Self.slot))
    #expect(attempts.count == Self.pausedAttempts + 1)
    let interval = NearFieldSlotRequest.attemptInterval
    #expect(attempts.pauses == Array(repeating: interval, count: Self.pausedAttempts))
  }

  @Test("A pause that outlasts every attempt is reported as the reader's pause")
  internal func endlessPauseIsReported() async {
    let attempts = Attempts()
    let answer = await Self.request(attempts) { _ in .failure(Self.readerPause) }
    #expect(answer == .failure(.readerPaused))
    #expect(attempts.count == NearFieldSlotRequest.attemptLimit)
  }

  @Test("A busy radio is retried and reported as busy")
  internal func busyRadioIsRetried() async {
    let attempts = Attempts()
    let answer = await Self.request(attempts) { _ in .failure(Self.busyRadio) }
    #expect(answer == .failure(.busy))
    #expect(attempts.count == NearFieldSlotRequest.attemptLimit)
  }

  @Test("Any other refusal ends the request at once")
  internal func otherRefusalEndsAtOnce() async {
    let attempts = Attempts()
    let answer = await Self.request(attempts) { _ in .failure(Self.entitlementMissing) }
    #expect(answer == .failure(.refused))
    #expect(attempts.count == 1)
    #expect(attempts.pauses.isEmpty)
  }
}
