// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// What each card operation reports back to its caller.
extension VirtualIDCard {
  /// The outcome of connecting to the card.
  public enum ConnectionResult: Equatable, Sendable {
    case connected(Snapshot)
    case incorrectCardAccessNumber
    case unavailable(FaultEffect)
  }

  /// Attempts remaining for each credential, read without side effects.
  public struct RetryReport: Equatable, Sendable {
    /// Attempts remaining for PIN 1.
    public let pin1: UInt8
    /// Attempts remaining for PIN 2.
    public let pin2: UInt8
    /// Attempts remaining for the PUK.
    public let puk: UInt8

    /// Creates a report from the three counters.
    public init(pin1: UInt8, pin2: UInt8, puk: UInt8) {
      self.pin1 = pin1
      self.pin2 = pin2
      self.puk = puk
    }
  }

  /// The outcome of probing the retry counters.
  public enum ProbeResult: Equatable, Sendable {
    case report(RetryReport)
    case unreadable
    case unavailable(FaultEffect)
  }

  /// The outcome of one credential operation at the card boundary.
  ///
  /// The retry floor refuses verification outright at one or two remaining
  /// attempts rather than risk blocking the credential.
  public enum CredentialOutcome: Equatable, Sendable {
    case success
    case alreadyActivated
    case invalidEntry
    case blocked
    case rejected(remaining: UInt8)
    case refusedLowAttempts(remaining: UInt8)
    case transportFailure(FaultEffect)
  }

  /// A credential outcome paired with the snapshot it produced.
  public struct MutationResult: Equatable, Sendable {
    /// The outcome at the card boundary.
    public let outcome: CredentialOutcome
    /// The state after the operation.
    public let snapshot: Snapshot

    /// Pairs an outcome with the resulting snapshot.
    public init(outcome: CredentialOutcome, snapshot: Snapshot) {
      self.outcome = outcome
      self.snapshot = snapshot
    }
  }

  /// The entry and new PINs offered to activate factory credentials.
  public struct ActivationRequest: Equatable, Sendable {
    /// The activation PIN offered to the card.
    public let entry: String
    /// The new PIN 1 to set, when PIN 1 needs activation.
    public let newPIN1: String?
    /// The new PIN 2 to set, when PIN 2 needs activation.
    public let newPIN2: String?

    /// Creates a request from the entry and the optional new PINs.
    public init(entry: String, newPIN1: String?, newPIN2: String?) {
      self.entry = entry
      self.newPIN1 = newPIN1
      self.newPIN2 = newPIN2
    }
  }

  /// Per-PIN activation outcomes with the snapshot they produced.
  public struct ActivationResult: Equatable, Sendable {
    /// The outcome for PIN 1.
    public let pin1: CredentialOutcome
    /// The outcome for PIN 2, or nil when PIN 2 was never attempted.
    public let pin2: CredentialOutcome?
    /// The state after the activation attempt.
    public let snapshot: Snapshot

    /// Pairs the per-PIN outcomes with the resulting snapshot.
    public init(
      pin1: CredentialOutcome,
      pin2: CredentialOutcome?,
      snapshot: Snapshot
    ) {
      self.pin1 = pin1
      self.pin2 = pin2
      self.snapshot = snapshot
    }
  }

  /// The outcome of registering the card on the device.
  public enum RegistrationResult: Equatable, Sendable {
    case success(Snapshot)
    case certificateUnavailable
    case tokenPublicationFailed(Snapshot)
    case transportFailure(FaultEffect)
  }

  /// The card boundary exercised by a qualified document signature.
  public enum SignatureResult: Equatable, Sendable {
    case success
    case invalidEntry
    case blocked
    case rejected(remaining: UInt8)
    case refusedLowAttempts(remaining: UInt8)
    case certificateUnavailable
    case transportFailure(FaultEffect)
  }
}
