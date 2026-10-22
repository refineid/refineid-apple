// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The transition tables of the formal RAPP state model (RAPP v26.10.22),
/// transcribed in model order so a rule here and a rule there can be compared
/// line for line.
internal enum RappModelTables {
  /// Pairing component rules.
  internal static let pairing: [RappRule<PairingState, PairingEvent>] = [
    RappRule(
      from: .unpaired,
      event: .startPairing,
      role: .custodian,
      condition: .userInitiated,
      destination: .offering,
      actions: [.generateOffer, .generatePairingCode, .advertisePairingMode, .displayPairingCode]
    ),
    RappRule(
      from: .offering,
      event: .offerExpiredOrCancelled,
      role: .custodian,
      destination: .unpaired,
      actions: [.destroyOffer, .hidePairingCode]
    ),
    RappRule(
      from: .offering,
      event: .attemptStarted,
      role: .custodian,
      destination: .exchanging,
      actions: [.reserveAttempt]
    ),
    RappRule(
      from: .unpaired,
      event: .codeEntered,
      role: .requester,
      condition: .userInitiated,
      destination: .exchanging,
      actions: [.readOffer, .beginCpaceInitiator]
    ),
    RappRule(
      from: .exchanging,
      event: .attemptFailed,
      role: .custodian,
      destination: .offering,
      actions: [.countFailedAttempt]
    ),
    RappRule(
      from: .exchanging,
      event: .lastAttemptFailed,
      role: .custodian,
      destination: .unpaired,
      actions: [.destroyOffer, .hidePairingCode, .startPairingBackoff, .showAttemptsExhausted]
    ),
    RappRule(
      from: .exchanging,
      event: .attemptFailed,
      role: .requester,
      condition: .untriedPairingCandidate,
      destination: .exchanging,
      actions: [.closeCandidate, .tryNextCandidate, .readOffer, .beginCpaceInitiator]
    ),
    RappRule(
      from: .exchanging,
      event: .lastCandidateFailed,
      role: .requester,
      destination: .unpaired,
      actions: [.closeCandidate, .showWrongCode]
    ),
    RappRule(
      from: .exchanging,
      event: .noCustodianTried,
      role: .requester,
      destination: .unpaired,
      actions: [.closeCandidate, .showNoneInPairingMode]
    ),
    RappRule(
      from: .exchanging,
      event: .offerExpiredOrCancelled,
      role: .custodian,
      destination: .unpaired,
      actions: [.destroyOffer, .hidePairingCode, .closeCandidate]
    ),
    RappRule(
      from: .exchanging,
      event: .keyConfirmed,
      role: .custodian,
      destination: .handshaking,
      actions: [.consumeOffer, .hidePairingCode, .derivePairingSecret, .beginPairingHandshake]
    ),
    RappRule(
      from: .exchanging,
      event: .keyConfirmed,
      role: .requester,
      destination: .handshaking,
      actions: [.derivePairingSecret, .beginPairingHandshake]
    ),
    RappRule(
      from: .handshaking,
      event: .handshakeAuthenticated,
      role: .requester,
      condition: .transcriptMatches,
      destination: .confirming,
      actions: [.deriveChannelIdentifiers, .destroyPairingSecret, .sendPairingHello]
    ),
    RappRule(
      from: .handshaking,
      event: .handshakeAuthenticated,
      role: .custodian,
      condition: .transcriptMatches,
      destination: .confirming,
      actions: [.deriveChannelIdentifiers, .destroyPairingSecret]
    ),
    RappRule(
      from: .handshaking,
      event: .handshakeFailed,
      role: .both,
      destination: .unpaired,
      actions: [.destroyPairingSecret, .destroyCandidateKeys, .closeCandidate]
    ),
    RappRule(
      from: .confirming,
      event: .helloVerified,
      role: .custodian,
      destination: .confirming,
      actions: [.sendPairingConfirm]
    ),
    RappRule(
      from: .confirming,
      event: .bothConfirmed,
      role: .both,
      condition: .grantedSetsEqual,
      destination: .storageConfirming,
      actions: [.storePairRecordAtomically, .sendPairingStored]
    ),
    RappRule(
      from: .confirming,
      event: .deniedAbortedOrTimedOut,
      role: .both,
      destination: .unpaired,
      actions: [.sendPairingAbortBestEffort, .destroyCandidateKeys, .closeCandidate]
    ),
    RappRule(
      from: .storageConfirming,
      event: .peerStorageConfirmed,
      role: .both,
      destination: .pairedDisconnected,
      actions: [.markRecordConfirmed, .closePairingChannel]
    ),
    RappRule(
      from: .storageConfirming,
      event: .deniedAbortedOrTimedOut,
      role: .both,
      destination: .unpaired,
      actions: [.revokeUnconfirmedPairRecord, .destroyPairKeys, .closeCandidate]
    ),
    RappRule(
      from: .pairedDisconnected,
      event: .sessionHealthy,
      role: .both,
      destination: .pairedConnected,
      actions: [.showConnected]
    ),
    RappRule(
      from: .pairedConnected,
      event: .sessionClosed,
      role: .both,
      destination: .pairedDisconnected,
      actions: [.showPairedDisconnected]
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
      role: .both,
      condition: .localUserAction,
      destination: .revoking,
      actions: [.markRecordRevoked, .withdrawIdentity, .showForgotten]
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
