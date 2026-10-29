// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The transition tables of the formal RAPP state model (RAPP v26.10.29),
/// transcribed in model order so a rule here and a rule there can be compared
/// line for line.
internal enum RappModelTables {
  /// Pairing component rules, in model order.
  internal static let pairing = pairingCeremony + pairingLifetime

  /// Pairing component rules from the offer to both endpoints storing the
  /// pairing (RAPP v26.10.29 §3, §4.3).
  private static let pairingCeremony: [RappRule<PairingState, PairingEvent>] = [
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
      actions: [.admitAttempt]
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
      actions: [.endFailedAttempt]
    ),
    RappRule(
      from: .offering,
      event: .attemptRefused,
      role: .custodian,
      destination: .offering,
      actions: [.answerBusy]
    ),
    RappRule(
      from: .exchanging,
      event: .attemptRefused,
      role: .custodian,
      destination: .exchanging,
      actions: [.answerBusy]
    ),
    RappRule(
      from: .exchanging,
      event: .candidateBusy,
      role: .requester,
      condition: .untriedPairingCandidate,
      destination: .exchanging,
      actions: [
        .closeCandidate, .deferCandidate, .tryNextCandidate, .readOffer, .beginCpaceInitiator,
      ]
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
      event: .searchInterrupted,
      role: .requester,
      destination: .unpaired,
      actions: [.closeCandidate]
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
  ]
}
