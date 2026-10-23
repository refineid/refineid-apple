// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

extension RappModelTables {
  /// Pairing component rules from a stored pairing's sessions to its end:
  /// recorded sessions, idle expiry, forgetting and revocation (RAPP
  /// v26.10.22 §4.5, §4.6).
  internal static let pairingLifetime: [RappRule<PairingState, PairingEvent>] = [
    RappRule(
      from: .pairedDisconnected,
      event: .sessionHealthy,
      role: .both,
      destination: .pairedConnected,
      actions: [.recordLastSession, .showConnected]
    ),
    RappRule(
      from: .pairedConnected,
      event: .sessionClosed,
      role: .both,
      destination: .pairedDisconnected,
      actions: [.recordLastSession, .showPairedDisconnected]
    ),
    RappRule(
      from: .pairedConnected,
      event: .peerWithdrawalNotice,
      role: .custodian,
      destination: .pairedDisconnected,
      actions: [.recordLastSession, .showPeerWithdrawn]
    ),
    RappRule(
      from: .pairedConnected,
      event: .forgetPairing,
      role: .both,
      condition: .localUserAction,
      destination: .revoked,
      actions: [
        .markRecordRevoked, .sendClosePairingRevoked, .closeSession, .destroyPairKeys,
        .withdrawIdentity, .showForgotten,
      ]
    ),
    RappRule(
      from: .pairedDisconnected,
      event: .forgetPairing,
      role: .custodian,
      condition: .localUserAction,
      destination: .revoking,
      actions: [.markRecordRevoked, .withdrawIdentity, .showForgotten]
    ),
    RappRule(
      from: .pairedDisconnected,
      event: .forgetPairing,
      role: .requester,
      condition: .localUserAction,
      destination: .revoked,
      actions: [.markRecordRevoked, .destroyPairKeys, .withdrawIdentity, .showForgotten]
    ),
    RappRule(
      from: .pairedConnected,
      event: .expiryCheck,
      role: .both,
      destination: .pairedConnected,
      actions: [.recordLastSession]
    ),
    RappRule(
      from: .pairedDisconnected,
      event: .expiryCheck,
      role: .both,
      destination: .pairedDisconnected,
      actions: []
    ),
    RappRule(
      from: .pairedDisconnected,
      event: .idleExpired,
      role: .both,
      destination: .revoking,
      actions: [.markRecordRevoked, .withdrawIdentity]
    ),
    RappRule(
      from: .revoking,
      event: .revocationNoticeSent,
      role: .both,
      destination: .revoked,
      actions: [.destroyPairKeys]
    ),
    RappRule(
      from: .revoking,
      event: .noticeWindowExpired,
      role: .both,
      destination: .revoked,
      actions: [.destroyPairKeys]
    ),
    RappRule(
      from: [.pairedDisconnected, .pairedConnected, .revoking],
      event: .peerRevocationNotice,
      role: .both,
      destination: .revoked,
      actions: [
        .markRecordRevoked, .closeSession, .destroyPairKeys, .withdrawIdentity, .showPeerForgot,
      ]
    ),
    RappRule(
      from: .revoked,
      event: .forgetPairing,
      role: .both,
      condition: .localUserAction,
      destination: .unpaired,
      actions: [.clearResidualPairRecord]
    ),
  ]
}
