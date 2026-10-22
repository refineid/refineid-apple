// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Asking the system for the near-field slot, through the two answers
/// that mean "not yet": the radio still held by an earlier field, and the
/// reader's pause after a field ends.
///
/// `nfcd` releases the radio asynchronously after a hold, and after any
/// field ends it refuses a new one for eight to eleven seconds, answering
/// `Error Domain=nfcd Code=47 "Reader mode temporarily disabled"`. Both
/// pass on their own, so the request waits them out for a bounded number
/// of attempts before it gives up; any other refusal ends it at once.
internal enum NearFieldSlotRequest {
  /// Why the request gave up.
  internal enum Refusal: Error, Equatable {
    /// The radio was still busy after every attempt.
    case busy

    /// The request's task was cancelled between two attempts.
    case cancelled

    /// The reader's pause outlasted every attempt.
    case readerPaused

    /// The system refused the slot for a reason that does not pass.
    case refused
  }

  /// How many times the slot is asked for before giving up.
  ///
  /// Covers a busy radio and the reader's pause after a field.
  internal static let attemptLimit = 12

  /// Wait between two attempts.
  internal static let attemptInterval: Duration = .seconds(1)

  /// The word the system uses when the radio is still held elsewhere.
  ///
  /// There is no error code for it, only the message, so this matches the
  /// message and treats everything else as a real refusal.
  internal static let busyErrorFragment = "busy"

  /// The error domain of the reader's pause after a field.
  internal static let readerPauseErrorDomain = "nfcd"

  /// The error code of the reader's pause after a field.
  internal static let readerPauseErrorCode = 47

  /// Whether `error` is the reader's pause after a field.
  internal static func isReaderPause(_ error: any Error) -> Bool {
    let failure = error as NSError
    return failure.domain == Self.readerPauseErrorDomain
      && failure.code == Self.readerPauseErrorCode
  }

  /// Whether `error` is the radio still being held elsewhere.
  internal static func isBusy(_ error: any Error) -> Bool {
    (error as NSError).localizedDescription
      .localizedCaseInsensitiveContains(Self.busyErrorFragment)
  }

  /// Asks for the slot with `attempt`, waiting ``attemptInterval`` with
  /// `pause` before each further attempt while the answer is busy or the
  /// reader's pause.
  internal static func request<Slot>(
    attempt: () async -> Result<Slot, any Error>,
    pause: (Duration) async -> Void
  ) async -> Result<Slot, Refusal> {
    var metPause = false
    for attemptNumber in 1...Self.attemptLimit {
      if attemptNumber > 1 {
        await pause(Self.attemptInterval)
        if Task.isCancelled { return .failure(.cancelled) }
      }
      switch await attempt() {
      case .success(let slot):
        #if DEBUG
          if attemptNumber > 1 {
            HolderTrace.say("slot request: given on attempt \(attemptNumber)")
          }
        #endif
        return .success(slot)

      case .failure(let error):
        #if DEBUG
          HolderTrace.say("slot request: attempt \(attemptNumber) refused: \(error)")
        #endif
        if Self.isReaderPause(error) {
          metPause = true
          #if DEBUG
            DevErrorLog.report(
              "near-field slot refused: reader paused (nfcd \(Self.readerPauseErrorCode))",
              source: .app)
          #endif
        } else if !Self.isBusy(error) {
          #if DEBUG
            DevErrorLog.report(
              "near-field slot refused: \(DevErrorLog.reason(error))", source: .app)
          #endif
          return .failure(.refused)
        }
      }
    }
    return .failure(metPause ? .readerPaused : .busy)
  }
}
