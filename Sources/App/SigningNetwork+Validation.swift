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
    try await withThrowingTaskGroup(of: Attempt.self) { group in
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
      return try await Self.winner(of: &group, plain: plain)
    }
  }

  /// The first success among the raced attempts, or the failure that
  /// says most about why there was none.
  private static func winner(
    of group: inout ThrowingTaskGroup<Attempt, Error>,
    plain: @escaping @Sendable () async throws -> Data
  ) async throws -> (data: Data, outcome: ValidatedOutcome) {
    var plainStarted = false
    var plainFailure: Error?
    var validatedFailure: Error?
    func startPlain() {
      guard !plainStarted else { return }
      plainStarted = true
      group.addTask {
        do {
          return .plain(.success(try await plain()))
        } catch {
          return .plain(.failure(error))
        }
      }
    }
    while let attempt = try await group.next() {
      switch attempt {
      case .headStartElapsed:
        startPlain()

      case .validated(.success(let data)):
        group.cancelAll()
        return (data, .validated)

      case .plain(.success(let data)):
        group.cancelAll()
        return (data, .plain)

      case .validated(.failure(let error)):
        guard Self.isResolutionFailure(error) else {
          group.cancelAll()
          throw error
        }
        validatedFailure = error
        startPlain()

      case .plain(.failure(let error)):
        plainFailure = error
      }
    }
    throw plainFailure ?? validatedFailure ?? Failure.unusableBody
  }
}
