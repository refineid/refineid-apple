// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) || os(iOS)
  import CardCore

  /// What the end of the session with the phone says, as the requester
  /// acts on it.
  ///
  /// The phone's own statements, a revocation and a withdrawal, are cases
  /// of their own, so nothing that reconnects after a loss can take them
  /// for one (RAPP v26.11.2 §4.5 item 6, §4.6 item 4).
  internal enum PhoneSessionEnd: Equatable, Sendable {
    /// Anything else, a lost network among it: the identity follows its
    /// grace and the phone is dialled again.
    case lost

    /// The phone forgot this computer: the pairing ends here too.
    case pairingRevoked

    /// This computer's `pairing_revoked` close for a pairing it forgot
    /// reached the phone: the record goes.
    case revocationNoticeDelivered

    /// An authenticated protocol violation, the phone's close or one this
    /// computer detected: the pairing stays, the identity follows its
    /// grace, and nothing is dialled until the phone next appears or a
    /// consumer asks (RAPP v26.11.2 §4.5 item 6).
    case violation

    /// The phone stopped serving, a verified withdrawal, or can serve no
    /// card (`card_unavailable`). Its identity leaves at once and nothing
    /// is dialled until the phone announces itself again.
    case withdrawn

    // MARK: Lifecycle

    internal init(_ reason: RappConnectionCoordinator.CloseReason) {
      if reason.peerRevokedPairing {
        self = .pairingRevoked
      } else if reason == .handshake(.revocationNoticeDelivered) {
        self = .revocationNoticeDelivered
      } else if reason.serviceWithdrawn || reason.cardUnavailable {
        self = .withdrawn
      } else if reason.protocolViolation {
        self = .violation
      } else {
        self = .lost
      }
    }
  }
#endif
