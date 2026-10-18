// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

extension RappModelTables {
  /// Session component rules.
  internal static let session: [RappRule<SessionState, SessionEvent>] = [
    RappRule(
      from: .absent,
      event: .connect,
      role: .requester,
      condition: .initiationPermitted,
      destination: .connecting,
      actions: [.selectOneTransport, .openTransport]
    ),
    RappRule(
      from: .absent,
      event: .transportAccepted,
      role: .proxy,
      condition: .pairingPaired,
      destination: .authenticating,
      actions: [.associatePairingFromRendezvous, .beginKkResponder]
    ),
    RappRule(
      from: .connecting,
      event: .transportConnected,
      role: .requester,
      destination: .authenticating,
      actions: [.beginKkInitiator]
    ),
    RappRule(
      from: .connecting,
      event: .transportFailed,
      role: .requester,
      destination: .closed,
      actions: [.destroySessionMaterial, .showConnectionStopped]
    ),
    RappRule(
      from: .connecting,
      event: .userDisconnect,
      role: .requester,
      destination: .closed,
      actions: [.abortCandidate, .destroySessionMaterial, .showConnectionStopped]
    ),
    RappRule(
      from: .authenticating,
      event: .handshakeComplete,
      role: .both,
      destination: .authenticating,
      actions: [.deriveSessionIdentifiers, .sendSessionReady]
    ),
    RappRule(
      from: .authenticating,
      event: .secondSessionDetected,
      role: .proxy,
      condition: .anotherSessionLive,
      destination: .closed,
      actions: [.sendErrorBusy, .destroySessionMaterial, .closeCandidate]
    ),
    RappRule(
      from: .authenticating,
      event: .readyVerified,
      role: .both,
      condition: .readyParametersMatch,
      destination: .healthy,
      actions: [.startAuthenticatedLiveness, .showConnected]
    ),
    RappRule(
      from: .authenticating,
      event: .candidateFailure,
      role: .both,
      destination: .closed,
      actions: [
        .destroySessionMaterial, .closeCandidate, .countCandidateFailureHint,
        .showConnectionStopped,
      ]
    ),
    RappRule(
      from: .authenticating,
      event: .busyReceived,
      role: .requester,
      destination: .closed,
      actions: [.destroySessionMaterial, .closeCandidate, .showConnectionStopped]
    ),
    RappRule(
      from: .authenticating,
      event: .peerCloseReceived,
      role: .both,
      destination: .closed,
      actions: [
        .recordPeerCloseReason, .destroySessionMaterial, .closeCandidate, .showConnectionStopped,
      ]
    ),
    RappRule(
      from: .authenticating,
      event: .transportFailed,
      role: .both,
      destination: .closed,
      actions: [.destroySessionMaterial, .showConnectionStopped]
    ),
    RappRule(
      from: .authenticating,
      event: .authenticatedProtocolViolation,
      role: .both,
      destination: .closing,
      actions: [.sendCloseBestEffort, .showDisconnecting]
    ),
    RappRule(
      from: .healthy,
      event: .livenessMissed,
      role: .both,
      destination: .checking,
      actions: [.blockNewOperations, .startBackoffAndDeadline, .showChecking]
    ),
    RappRule(
      from: .checking,
      event: .livenessRestored,
      role: .both,
      condition: .deadlineNotExpired,
      destination: .healthy,
      actions: [.resetBackoff, .showConnected]
    ),
    RappRule(
      from: .checking,
      event: .livenessDeadlineExpired,
      role: .both,
      destination: .closing,
      actions: [.showDisconnecting]
    ),
    RappRule(
      from: [.healthy, .checking],
      event: .userDisconnect,
      role: .both,
      destination: .closing,
      actions: [.sendCloseBestEffort, .showDisconnecting]
    ),
    RappRule(
      from: [.healthy, .checking],
      event: .localCloseRequested,
      role: .both,
      destination: .closing,
      actions: [.sendCloseBestEffort, .showDisconnecting]
    ),
    RappRule(
      from: [.healthy, .checking],
      event: .peerCloseReceived,
      role: .both,
      destination: .closing,
      actions: [.recordPeerCloseReason, .showDisconnecting]
    ),
    RappRule(
      from: .closing,
      event: .peerCloseReceived,
      role: .both,
      destination: .closing,
      actions: []
    ),
    RappRule(
      from: [.healthy, .checking],
      event: .credentialRejected,
      role: .proxy,
      destination: .closing,
      actions: [
        .retainRevocationKey, .destroyPairKeys, .showRevoked, .sendCloseBestEffort,
        .showDisconnecting,
      ]
    ),
    RappRule(
      from: [.healthy, .checking],
      event: .cardCompletionAmbiguous,
      role: .proxy,
      destination: .closing,
      actions: [.showDisconnecting]
    ),
    RappRule(
      from: [.healthy, .checking],
      event: .transportFailed,
      role: .both,
      destination: .closing,
      actions: [.noteCloseNoticeImpossible, .showDisconnecting]
    ),
    RappRule(
      from: [.healthy, .checking],
      event: .sessionIntegrityFailed,
      role: .both,
      destination: .closing,
      actions: [.noteCloseNoticeImpossible, .showDisconnecting]
    ),
    RappRule(
      from: [.healthy, .checking],
      event: .authenticatedProtocolViolation,
      role: .both,
      destination: .closing,
      actions: [.sendCloseBestEffort, .showDisconnecting]
    ),
    RappRule(
      from: [.healthy, .checking],
      event: .closeRequestedByPairing,
      role: .both,
      destination: .closing,
      actions: [.showDisconnecting]
    ),
    RappRule(
      from: [.connecting, .authenticating],
      event: .closeRequestedByPairing,
      role: .both,
      destination: .closed,
      actions: [.destroySessionMaterial, .closeCandidate, .showConnectionStopped]
    ),
    RappRule(
      from: [.healthy, .checking],
      event: .localSecurityShutdown,
      role: .both,
      destination: .closing,
      actions: [.noteCloseNoticeImpossible, .showDisconnecting]
    ),
    RappRule(
      from: [.connecting, .authenticating],
      event: .localSecurityShutdown,
      role: .both,
      destination: .closed,
      actions: [.destroySessionMaterial, .showConnectionStopped]
    ),
    RappRule(
      from: .closing,
      event: .transportFailed,
      role: .both,
      destination: .closing,
      actions: [.proceedWithoutCloseNotice]
    ),
    RappRule(
      from: .closing,
      event: .closeCompleteOrDeadline,
      role: .both,
      destination: .closed,
      actions: [
        .destroySessionMaterial, .destroyCredentialBuffers, .persistTerminalSessionRecord,
        .showConnectionStopped,
      ]
    ),
  ]
}
