// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The credential-bearing card operations: VERIFY, CHANGE REFERENCE
/// DATA, and RESET RETRY COUNTER.
///
/// Separate from the credential-free operations on purpose: every
/// parameter here is a noncopyable one-shot transmission, so one user
/// entry can reach the card at most once, and the caller must have
/// cleared the retry floor for whichever credential the command
/// presents.
///
/// Every flow knows the card's reference numbering before it consumes
/// the credential into its one command: VERIFY resolves it
/// (`resolveCredentialReferences()`, counter-safe, remembered for the
/// session), and the change and unblock flows take it from the
/// `CardPinLengths` read in the same session, so a resolution probe can
/// never cost a typed entry.
extension CardOperations {
  /// Verifies PIN1, consuming the one-shot credential.
  ///
  /// Sends VERIFY with the numbering's credential block (the
  /// noncopyable transport value guarantees at most one card command).
  /// Returns normally only on `9000`; a wrong PIN throws `pinRejected`
  /// carrying the remaining attempts, and any other answer throws
  /// `pinVerifyFailed`. The caller must already have cleared the retry
  /// floor.
  public func verifyPin1(_ transmission: consuming Pin1Transmission) throws {
    let references = try resolveCredentialReferences()
    let command = CredentialBearingCommand.verifyPin1(
      transmission,
      references: references
    )
    let raw = try channel.transmit(command.intoTransportPayload())
    guard let response = ResponseApdu(raw: raw) else {
      throw CardOperationError.malformedResponse
    }
    switch response.statusWord {
    case .success:
      referenceMemo.probedRetryCounters[.pin1] = .verified
      return

    case .pinIncorrect(let remaining):
      referenceMemo.probedRetryCounters[.pin1] = .remaining(remaining)
      throw CardOperationError.pinRejected(remaining: remaining)

    case .authenticationBlocked:
      referenceMemo.probedRetryCounters[.pin1] = .locked
      throw CardOperationError.pinBlocked

    default:
      referenceMemo.probedRetryCounters[.pin1] = nil
      throw CardOperationError.pinVerifyFailed(response.statusWord)
    }
  }

  /// Verifies PIN2, consuming the one-shot credential.
  ///
  /// PIN2 authorises the qualified-signature key; it is verified
  /// immediately before the one signature and never cached. Unlike the
  /// PIN1 path, an invalidated answer is an expected state here - a
  /// card whose signature slot was never activated gives it - so it
  /// maps to `credentialInvalidated`. The caller must already have
  /// cleared the retry floor.
  public func verifyPin2(_ transmission: consuming Pin2Transmission) throws {
    let references = try resolveCredentialReferences()
    let command = CredentialBearingCommand.verifyPin2(
      transmission,
      references: references
    )
    let raw = try channel.transmit(command.intoTransportPayload())
    guard let response = ResponseApdu(raw: raw) else {
      throw CardOperationError.malformedResponse
    }
    switch response.statusWord {
    case .success:
      referenceMemo.probedRetryCounters[.pin2] = .verified
      return

    case .pinIncorrect(let remaining):
      referenceMemo.probedRetryCounters[.pin2] = .remaining(remaining)
      throw CardOperationError.pinRejected(remaining: remaining)

    case .authenticationBlocked:
      referenceMemo.probedRetryCounters[.pin2] = .locked
      throw CardOperationError.pinBlocked

    case .referenceDataInvalidated:
      referenceMemo.probedRetryCounters[.pin2] = .invalidated
      throw CardOperationError.credentialInvalidated

    default:
      referenceMemo.probedRetryCounters[.pin2] = nil
      throw CardOperationError.pinVerifyFailed(response.statusWord)
    }
  }

  /// Changes PIN1: the card checks `current` and replaces it with `new`
  /// in one command (CHANGE REFERENCE DATA, S1 v4.2 §3.5.3; Idemia
  /// organizational cards specification §4.1.7).
  ///
  /// On success the retry counter is at its maximum and the verified
  /// flag is cleared - the new PIN is set but not presented. A wrong
  /// current PIN throws `pinRejected` and costs one attempt; the caller
  /// must already have cleared the retry floor for PIN1. An entry whose
  /// length `lengths` does not accept throws `pinLengthRefused` before
  /// any command; the card is addressed under `lengths`' numbering.
  public func changePin1(
    current: consuming Pin1Transmission,
    new: consuming Pin1Transmission,
    lengths: CardPinLengths
  ) throws {
    try lengths.check(.pin1, digitCount: current.store.bytes.count)
    try lengths.check(.pin1, digitCount: new.store.bytes.count)
    let references = lengths.numbering
    try performCredentialUpdate(
      CredentialBearingCommand.changePin1(
        current: current,
        new: new,
        references: references
      )
    )
  }

  /// Changes PIN2: the card checks `current` and replaces it with `new`
  /// in one command (CHANGE REFERENCE DATA, S1 v4.2 §3.5.3).
  ///
  /// Same semantics as `changePin1`, against the PIN2 slot; the retry
  /// floor the caller must have cleared is PIN2's.
  public func changePin2(
    current: consuming Pin2Transmission,
    new: consuming Pin2Transmission,
    lengths: CardPinLengths
  ) throws {
    try lengths.check(.pin2, digitCount: current.store.bytes.count)
    try lengths.check(.pin2, digitCount: new.store.bytes.count)
    let references = lengths.numbering
    try performCredentialUpdate(
      CredentialBearingCommand.changePin2(
        current: current,
        new: new,
        references: references
      )
    )
  }

  /// Unblocks PIN1: the card checks the unblocking credential, resets
  /// PIN1's retry counter, and sets `new` as its value.
  ///
  /// The citizen card does all of that in one RESET RETRY COUNTER
  /// (S1 v4.2 §3.5.4). The organization card takes two commands: the
  /// unblock credential is verified as its own object first, then the
  /// reset carries only the new PIN (S4-2 v4.0 §4.3.2; Idemia
  /// organizational cards specification §4.1.6) - a refused code ends
  /// the flow before the reset. Either way a wrong code throws
  /// `pinRejected` carrying the code's own remaining count, and
  /// exhausting it is terminal for the card - the caller must have
  /// cleared the retry floor for the unblocking credential, not the
  /// target PIN. On success the new PIN is set but not presented. An
  /// entry whose length `lengths` does not accept throws
  /// `pinLengthRefused` before any command; the card is addressed under
  /// `lengths`' numbering.
  public func unblockPin1(
    puk: consuming PukTransmission,
    new: consuming Pin1Transmission,
    lengths: CardPinLengths
  ) throws {
    try lengths.check(.puk, digitCount: puk.store.bytes.count)
    try lengths.check(.pin1, digitCount: new.store.bytes.count)
    let references = lengths.numbering
    switch references {
    case .citizen:
      try performCredentialUpdate(
        CredentialBearingCommand.unblockPin1(
          puk: puk,
          new: new,
          references: references
        )
      )

    case .organization:
      try performOrganizationUnblock(
        verify: CredentialBearingCommand.verifyUnblockCredential(
          puk,
          references: references
        ),
        reset: CredentialBearingCommand.resetPin1AfterVerifiedUnblock(
          new: new,
          references: references
        )
      )
    }
  }

  /// Unblocks PIN2: the card checks the unblocking credential, resets
  /// PIN2's retry counter, and sets `new` as its value.
  ///
  /// Same semantics as `unblockPin1`, against the PIN2 slot.
  public func unblockPin2(
    puk: consuming PukTransmission,
    new: consuming Pin2Transmission,
    lengths: CardPinLengths
  ) throws {
    try lengths.check(.puk, digitCount: puk.store.bytes.count)
    try lengths.check(.pin2, digitCount: new.store.bytes.count)
    let references = lengths.numbering
    switch references {
    case .citizen:
      try performCredentialUpdate(
        CredentialBearingCommand.unblockPin2(
          puk: puk,
          new: new,
          references: references
        )
      )

    case .organization:
      try performOrganizationUnblock(
        verify: CredentialBearingCommand.verifyUnblockCredential(
          puk,
          references: references
        ),
        reset: CredentialBearingCommand.resetPin2AfterVerifiedUnblock(
          new: new,
          references: references
        )
      )
    }
  }

  /// Sends the organization card's two-command unblock in order,
  /// stopping at the first refused answer: only an accepted unblock
  /// credential lets the reset go out.
  ///
  /// Both commands were built - and their transmissions consumed -
  /// before anything reached the card, keeping the one-entry-one-
  /// command chain linear; a `verify` refusal simply drops the unsent
  /// reset command.
  private func performOrganizationUnblock(
    verify: consuming CredentialBearingCommand,
    reset: consuming CredentialBearingCommand
  ) throws {
    try performCredentialUpdate(verify)
    try performCredentialUpdate(reset)
  }

  /// Sends one credential update and classifies the card's answer: it
  /// either accepts, counts down the presented credential, or reports
  /// the slot blocked or invalidated.
  private func performCredentialUpdate(
    _ command: consuming CredentialBearingCommand
  ) throws {
    referenceMemo.probedRetryCounters.removeAll()
    let raw = try channel.transmit(command.intoTransportPayload())
    guard let response = ResponseApdu(raw: raw) else {
      throw CardOperationError.malformedResponse
    }
    switch response.statusWord {
    case .success:
      return

    case .pinIncorrect(let remaining):
      throw CardOperationError.pinRejected(remaining: remaining)

    case .authenticationBlocked:
      throw CardOperationError.pinBlocked

    case .referenceDataInvalidated:
      throw CardOperationError.credentialInvalidated

    default:
      throw CardOperationError.credentialUpdateFailed(response.statusWord)
    }
  }
}
