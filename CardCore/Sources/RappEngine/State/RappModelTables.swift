// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The transition tables of the formal RAPP state model, transcribed in model
/// order so a rule here and a rule there can be compared line for line.
internal enum RappModelTables {
  /// Pairing component rules.
  internal static let pairing: [RappRule<PairingState, PairingEvent>] = [
    RappRule(
      from: .unpaired,
      event: .createOffer,
      role: .requester,
      condition: .userInitiated,
      destination: .offerActive,
      actions: [.generateOfferId, .generatePairingSecret, .startOfferExpiry, .displayPairingCode]
    ),
    RappRule(
      from: .unpaired,
      event: .offerScanned,
      role: .proxy,
      condition: .offerValidAndSupported,
      destination: .handshaking,
      actions: [.selectOneCandidate, .connectCandidate, .preparePairingResponder]
    ),
    RappRule(
      from: .offerActive,
      event: .candidateConnected,
      role: .requester,
      condition: .offerLive,
      destination: .handshaking,
      actions: [.beginPairingHandshakeInitiator]
    ),
    RappRule(
      from: .offerActive,
      event: .offerExpiredOrCancelled,
      role: .requester,
      destination: .unpaired,
      actions: [.destroyPairingSecret, .invalidateOffer, .hidePairingCode]
    ),
    RappRule(
      from: .handshaking,
      event: .handshakeAuthenticated,
      role: .both,
      condition: .transcriptMatches,
      destination: .confirming,
      actions: [
        .deriveChannelIdentifiers, .destroyPairingSecret,
        .stopAcceptingCandidates, .hidePairingCode,
        .sendPairingHello, .showPeerAndRequestedGrants,
      ]
    ),
    RappRule(
      from: .handshaking,
      event: .handshakeFailed,
      role: .requester,
      destination: .offerActive,
      actions: [.discardCandidate, .retainOffer]
    ),
    RappRule(
      from: .handshaking,
      event: .handshakeFailed,
      role: .proxy,
      destination: .unpaired,
      actions: [.discardCandidate]
    ),
    RappRule(
      from: .handshaking,
      event: .offerExpiredOrCancelled,
      role: .requester,
      destination: .unpaired,
      actions: [.destroyPairingSecret, .invalidateOffer, .closeCandidate]
    ),
    RappRule(
      from: .confirming,
      event: .bothUsersConfirmed,
      role: .both,
      condition: .grantedSetsEqual,
      destination: .storageConfirming,
      actions: [.storePairRecordAtomically, .invalidateOffer, .sendPairingStored]
    ),
    RappRule(
      from: .storageConfirming,
      event: .peerStorageConfirmed,
      role: .both,
      destination: .pairedDisconnected,
      actions: [.closePairingChannel]
    ),
    RappRule(
      from: .storageConfirming,
      event: .deniedAbortedOrTimedOut,
      role: .both,
      destination: .unpaired,
      actions: [
        .retainRevocationKey, .revokeUnconfirmedPairRecord, .destroyPairKeys, .clearPairMetadata,
        .closeCandidate,
      ]
    ),
    RappRule(
      from: .storageConfirming,
      event: .authenticatedProtocolViolation,
      role: .both,
      destination: .revoked,
      actions: [.retainRevocationKey, .destroyPairKeys, .closeCandidate, .showRevoked]
    ),
    RappRule(
      from: .confirming,
      event: .deniedAbortedOrTimedOut,
      role: .both,
      destination: .unpaired,
      actions: [
        .sendPairingAbortBestEffort, .destroyCandidateKeys, .invalidateOffer, .closeCandidate,
      ]
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
      from: .pairedDisconnected,
      event: .forgetPairing,
      role: .both,
      condition: .localUserAction,
      destination: .unpaired,
      actions: [.retainRevocationKey, .destroyPairKeys, .destroyRelayTokens, .clearPairMetadata]
    ),
    RappRule(
      from: .pairedConnected,
      event: .forgetPairing,
      role: .both,
      condition: .localUserAction,
      destination: .unpaired,
      actions: [
        .sendCloseBestEffort, .closeSession, .retainRevocationKey, .destroyPairKeys,
        .destroyRelayTokens, .clearPairMetadata,
      ]
    ),
    RappRule(
      from: .pairedConnected,
      event: .authenticatedProtocolViolation,
      role: .both,
      destination: .revoked,
      actions: [
        .sendCloseBestEffort, .closeSession, .retainRevocationKey, .destroyPairKeys, .showRevoked,
      ]
    ),
    RappRule(
      from: .pairedConnected,
      event: .localRevoke,
      role: .both,
      condition: .localUserAction,
      destination: .revoked,
      actions: [
        .sendCloseBestEffort, .closeSession, .retainRevocationKey, .destroyPairKeys, .showRevoked,
      ]
    ),
    RappRule(
      from: .pairedDisconnected,
      event: .localRevoke,
      role: .both,
      condition: .localUserAction,
      destination: .revoked,
      actions: [.retainRevocationKey, .destroyPairKeys, .showRevoked]
    ),
    RappRule(
      from: .pairedConnected,
      event: .peerRevocationNotice,
      role: .both,
      destination: .revoked,
      actions: [.recordPeerInitiated, .closeSession, .destroyPairKeys, .showRevoked]
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
