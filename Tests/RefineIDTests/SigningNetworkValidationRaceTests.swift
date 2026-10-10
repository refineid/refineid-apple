// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RefineID

/// The validated exchange and its unvalidated companion, raced.
@Suite
internal struct SigningNetworkValidationRaceTests {
  private enum Fixture {
    static let validatedBody = Data("validated".utf8)
    static let plainBody = Data("plain".utf8)
    static let headStart: Duration = .milliseconds(50)
    static let stalled: Duration = .seconds(30)
    static let memoryLifetime: Duration = .seconds(10)
    static let host = "authority.invalid"

    static func resolutionFailure() -> Error {
      NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
    }
  }

  /// A validated answer wins when it comes first.
  @Test
  internal func validatedAnswerWins() async throws {
    let answer = try await SigningNetwork.firstAnswer(
      headStart: Fixture.headStart,
      validated: { Fixture.validatedBody },
      plain: { Fixture.plainBody }
    )
    #expect(answer.data == Fixture.validatedBody)
    #expect(answer.outcome == .validated)
  }

  /// A validated lookup that never answers costs the head start, not
  /// its own timeout.
  @Test
  internal func stalledValidationLosesAfterHeadStart() async throws {
    let started = ContinuousClock.now
    let answer = try await SigningNetwork.firstAnswer(
      headStart: Fixture.headStart,
      validated: {
        try await Task.sleep(for: Fixture.stalled)
        return Fixture.validatedBody
      },
      plain: { Fixture.plainBody }
    )
    #expect(answer.data == Fixture.plainBody)
    #expect(answer.outcome == .plain)
    #expect(ContinuousClock.now - started < Fixture.stalled)
  }

  /// A resolution failure leaves the exchange to the unvalidated attempt.
  @Test
  internal func resolutionFailureFallsBack() async throws {
    let answer = try await SigningNetwork.firstAnswer(
      headStart: Fixture.headStart,
      validated: { throw Fixture.resolutionFailure() },
      plain: { Fixture.plainBody }
    )
    #expect(answer.outcome == .plain)
  }

  /// The service's own refusal over a validated lookup is the answer.
  @Test
  internal func serviceRefusalEndsTheRace() async {
    await #expect(throws: SigningNetwork.Failure.httpStatus(403)) {
      try await SigningNetwork.firstAnswer(
        headStart: Fixture.headStart,
        validated: { throw SigningNetwork.Failure.httpStatus(403) },
        plain: { Fixture.plainBody }
      )
    }
  }

  /// With both attempts failed, the unvalidated attempt's failure is
  /// reported.
  @Test
  internal func bothFailingReportsThePlainFailure() async {
    await #expect(throws: SigningNetwork.Failure.unusableBody) {
      try await SigningNetwork.firstAnswer(
        headStart: Fixture.headStart,
        validated: { throw Fixture.resolutionFailure() },
        plain: { throw SigningNetwork.Failure.unusableBody }
      )
    }
  }

  /// A host that failed validation is asked unvalidated until the
  /// memory lapses.
  @Test
  internal func memoryLapses() {
    let memory = SigningNetwork.ValidationMemory(lifetime: Fixture.memoryLifetime)
    let now = ContinuousClock.now
    #expect(!memory.skipsValidation(for: Fixture.host, at: now))
    memory.recordFailure(for: Fixture.host, at: now)
    #expect(memory.skipsValidation(for: Fixture.host, at: now))
    #expect(
      !memory.skipsValidation(
        for: Fixture.host, at: now.advanced(by: Fixture.memoryLifetime)
      )
    )
  }
}
