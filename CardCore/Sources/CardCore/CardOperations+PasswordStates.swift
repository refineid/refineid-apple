// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The retry counters of an organization card on the contactless
/// interface, read before PACE.
///
/// Such a card answers `6985` to the VERIFY status form until PACE has run
/// and has no card access number to run it with, but MSE:Set AT naming a
/// password answers with that password's state (BSI TR-03110-3 section
/// B.14.1). A try is taken only at the first GENERAL AUTHENTICATE, which
/// nothing here sends.
extension CardOperations {
  /// The reading behind a status form answered `answer`, when that answer
  /// is the sealed card's `6985` and the card reports a state for `role`.
  ///
  /// A card that names the password reference is on the organization
  /// numbering (FINEID S4-2 v4.0 section 4.2), which resolves it for the
  /// session. Nil for any other answer, inside a channel a credential
  /// opened, and when the card reports no state: the caller then classifies
  /// `answer` as it stands, and the retry floor refuses it as unreadable.
  internal func sealedReading(
    of role: CredentialRole,
    after answer: StatusWord
  ) -> RetryProbeOutcome? {
    guard channelPin == nil, answer == .conditionsNotSatisfied else { return nil }
    guard let state = try? readPasswordState(of: role) else { return nil }
    if case .other = state { return nil }
    referenceMemo.resolved = .organization
    return state
  }

  /// All three counters after a credential opened the channel, read over
  /// the plain transport under it.
  ///
  /// The first plain command ends secure messaging and the card returns to
  /// its sealed state, so this is the channel's last use. The card leaves
  /// the channel at the main file: a sealed card refuses that select in the
  /// clear, and EF.CardAccess cannot be reached from DF.ESIGN (observed on
  /// hardware). A channel with no plain transport recorded is read as it
  /// stands.
  public func credentialsAfterChannel() throws -> CredentialProbeReport {
    guard let plainChannel else { return try probeCredentials() }
    try selectMainFile()
    return try CardOperations(channel: plainChannel).probeCredentials()
  }

  /// The state MSE:Set AT answers for the organization reference of `role`.
  private func readPasswordState(of role: CredentialRole) throws -> RetryProbeOutcome {
    guard
      let command = PaceCommand.securityEnvironment(
        suite: try passwordStateSuite(),
        passwordReference: FineidValues.organizationReference(for: role)
      )
    else {
      throw CardOperationError.malformedResponse
    }
    return RetryProbeOutcome(
      passwordStateAnswer: try ContinuedResponse.transmitting(command, over: channel).statusWord)
  }

  /// The suite PACE would run, from EF.CardAccess, read once per session.
  private func passwordStateSuite() throws -> PaceInfo {
    if let known = referenceMemo.passwordStateSuite {
      return known
    }
    guard let suite = try readCardAccess().genericMappingSuite else {
      throw PaceEstablishment.Failure.noSupportedSuite
    }
    referenceMemo.passwordStateSuite = suite
    return suite
  }
}

extension RetryProbeOutcome {
  /// The state a password's MSE:Set AT answer reports (BSI TR-03110-3
  /// section B.14.1): `9000` is the initial tries, five on the organization
  /// card (FINEID S4-2 v4.0 section 4.3), `63CX` is X tries left, and
  /// `6283` a deactivated password.
  internal init(passwordStateAnswer answer: StatusWord) {
    switch answer {
    case .success:
      self =
        RetryCount(attemptsRemaining: RetryCount.pristineAllowance).map(Self.remaining)
        ?? .noInformation

    case .pinIncorrect(let remaining):
      self = remaining.isBlocked ? .locked : .remaining(remaining)

    case .authenticationBlocked:
      self = .locked

    case .other(PaceValues.swPasswordDeactivated):
      self = .invalidated

    default:
      self = .other(answer.encoded)
    }
  }
}
