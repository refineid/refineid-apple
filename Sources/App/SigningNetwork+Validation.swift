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

  /// Hosts whose validated lookup recently failed or lost to the
  /// unvalidated one.
  ///
  /// A resolver that cannot validate a name fails it the same way on
  /// the next exchange, and one signature makes a dozen exchanges.
  internal final class ValidationMemory: Sendable {
    private let skipUntil = OSAllocatedUnfairLock(
      initialState: [String: ContinuousClock.Instant]()
    )
    private let lifetime: Duration

    /// A memory that forgets a host after `lifetime`.
    internal init(lifetime: Duration) {
      self.lifetime = lifetime
    }

    /// Whether `host` is still remembered as failing validation at `now`.
    internal func skipsValidation(
      for host: String,
      at now: ContinuousClock.Instant
    ) -> Bool {
      skipUntil.withLock { remembered in
        guard let until = remembered[host] else { return false }
        guard now < until else {
          remembered[host] = nil
          return false
        }
        return true
      }
    }

    /// Remembers that `host` failed validation at `now`.
    internal func recordFailure(
      for host: String,
      at now: ContinuousClock.Instant
    ) {
      let until = now.advanced(by: lifetime)
      skipUntil.withLock { $0[host] = until }
    }
  }

  /// One finished attempt of a raced exchange.
  private enum Attempt {
    case validated(Result<Data, Error>)
    case plain(Result<Data, Error>)
  }

  /// Seconds a host is remembered as failing validation.
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

  /// The process-wide record of hosts whose resolver cannot validate.
  internal static let validationMemory = ValidationMemory(
    lifetime: .seconds(Self.validationMemorySeconds)
  )

  /// The first usable answer of a validated exchange and an unvalidated
  /// one started `headStart` later.
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
        do {
          try await Task.sleep(for: headStart)
          return .plain(.success(try await plain()))
        } catch {
          return .plain(.failure(error))
        }
      }
      return try await Self.winner(of: &group)
    }
  }

  /// The first success among the raced attempts, or the failure that
  /// says most about why there was none.
  private static func winner(
    of group: inout ThrowingTaskGroup<Attempt, Error>
  ) async throws -> (data: Data, outcome: ValidatedOutcome) {
    var plainFailure: Error?
    var validatedFailure: Error?
    while let attempt = try await group.next() {
      switch attempt {
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

      case .plain(.failure(let error)):
        plainFailure = error
      }
    }
    throw plainFailure ?? validatedFailure ?? Failure.unusableBody
  }
}
