// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import os

extension SigningNetwork {
  /// Which of the two lookups produced an exchange's answer.
  internal enum ValidatedOutcome: Equatable, Sendable {
    /// The DNSSEC-validated exchange answered.
    case validated

    /// The unvalidated exchange answered, the validated one having
    /// failed to resolve or not answered first.
    case plain
  }

  /// Whether the resolver recently failed a validated lookup.
  ///
  /// DNSSEC validation belongs to the resolver, not to the host asked:
  /// one that cannot validate fails every name the same way, and one
  /// signature makes a dozen exchanges with different hosts.
  internal final class ValidationMemory: Sendable {
    private let skipUntil = OSAllocatedUnfairLock<ContinuousClock.Instant?>(
      initialState: nil
    )
    private let lifetime: Duration

    /// A memory that forgets the failure after `lifetime`.
    internal init(lifetime: Duration) {
      self.lifetime = lifetime
    }

    /// Whether validation is still remembered as failing at `now`.
    internal func skipsValidation(at now: ContinuousClock.Instant) -> Bool {
      skipUntil.withLock { remembered in
        guard let until = remembered else { return false }
        guard now < until else {
          remembered = nil
          return false
        }
        return true
      }
    }

    /// Remembers that validation failed at `now`.
    internal func recordFailure(at now: ContinuousClock.Instant) {
      let until = now.advanced(by: lifetime)
      skipUntil.withLock { $0 = until }
    }
  }

  /// One finished attempt of a raced exchange.
  private enum Attempt {
    case validated(Result<Data, Error>)
    case plain(Result<Data, Error>)
    case headStartElapsed
  }

  /// What one finished attempt means for the race.
  private enum Decision {
    /// The unvalidated attempt waits to be started.
    case startPlain

    /// The race goes on.
    case keep

    /// This answer ends the race.
    case answer(Data, ValidatedOutcome)

    /// This failure ends the race.
    case refuse(Error)
  }

  /// The race's running state.
  private struct RaceState {
    /// Whether the unvalidated attempt has been started.
    var plainStarted = false

    /// The unvalidated attempt's failure, if it has one.
    var plainFailure: Error?

    /// The validated attempt's resolution failure, if it had one.
    var validatedFailure: Error?
  }

  /// Seconds the resolver is remembered as failing validation.
  private static let validationMemorySeconds: Int64 = 600

  /// Milliseconds the validated exchange runs alone.
  private static let validatedHeadStartMilliseconds: Int64 = 500

  /// How long the validated exchange runs alone before the unvalidated
  /// one starts beside it.
  ///
  /// A validated lookup that works answers within tenths of a second;
  /// one that does not never answers before its timeout.
  internal static let validatedHeadStart: Duration = .milliseconds(
    Self.validatedHeadStartMilliseconds
  )

  /// The process-wide record of whether the resolver can validate.
  internal static let validationMemory = ValidationMemory(
    lifetime: .seconds(Self.validationMemorySeconds)
  )

  /// The first usable answer of a validated exchange and an unvalidated
  /// one started `headStart` later, or as soon as the validated one
  /// fails to resolve.
  ///
  /// The validated exchange's own answer - a refusal, a bad status, a
  /// body over the limit - ends the race; only a resolution failure
  /// leaves it to the unvalidated one.
  internal static func firstAnswer(
    headStart: Duration,
    validated: @escaping @Sendable () async throws -> Data,
    plain: @escaping @Sendable () async throws -> Data
  ) async throws -> (data: Data, outcome: ValidatedOutcome) {
    let plainAttempt: @Sendable () async -> Attempt = {
      do {
        return .plain(.success(try await plain()))
      } catch {
        return .plain(.failure(error))
      }
    }
    // The group lives in this body for its whole life: a child is added
    // directly, never through a reference another scope holds across a
    // suspension, and every child is awaited before the group ends.
    return try await withThrowingTaskGroup(of: Attempt.self) { group in
      group.addTask {
        do {
          return .validated(.success(try await validated()))
        } catch {
          return .validated(.failure(error))
        }
      }
      group.addTask {
        try? await Task.sleep(for: headStart)
        return .headStartElapsed
      }
      var state = RaceState()
      while let attempt = try await group.next() {
        switch Self.decision(for: attempt, state: &state) {
        case .startPlain:
          group.addTask { await plainAttempt() }

        case .keep:
          continue

        case .answer(let data, let outcome):
          group.cancelAll()
          return (data, outcome)

        case .refuse(let error):
          group.cancelAll()
          throw error
        }
      }
      throw state.plainFailure ?? state.validatedFailure ?? Failure.unusableBody
    }
  }

  /// What `attempt` means for `state`.
  ///
  /// Pure: it reads the attempt and moves the state on, and takes no
  /// part in the group, so the group is driven from one scope alone.
  private static func decision(
    for attempt: Attempt,
    state: inout RaceState
  ) -> Decision {
    switch attempt {
    case .headStartElapsed:
      guard !state.plainStarted else { return .keep }
      state.plainStarted = true
      return .startPlain

    case .validated(.success(let data)):
      return .answer(data, .validated)

    case .plain(.success(let data)):
      return .answer(data, .plain)

    case .validated(.failure(let error)):
      guard Self.isResolutionFailure(error) else { return .refuse(error) }
      state.validatedFailure = error
      guard !state.plainStarted else { return .keep }
      state.plainStarted = true
      return .startPlain

    case .plain(.failure(let error)):
      state.plainFailure = error
      return .keep
    }
  }
}
