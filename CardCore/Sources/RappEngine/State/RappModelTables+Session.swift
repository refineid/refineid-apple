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
      actions: [.openTransport]
    ),
    RappRule(
      from: .absent,
      event: .preambleReceived,
      role: .custodian,
      condition: .pairingRouted,
      destination: .authenticating,
      actions: [.beginKkResponder]
    ),
    RappRule(
      from: .connecting,
      event: .transportConnected,
      role: .requester,
      destination: .authenticating,
      actions: [.sendSessionPreamble, .beginKkInitiator]
    ),
    RappRule(
      from: .connecting,
      event: .transportFailed,
      role: .requester,
      destination: .closed,
      actions: [.destroySessionMaterial, .showConnectionStopped]
    ),
    RappRule(
      from: .authenticating,
      event: .handshakeComplete,
      role: .custodian,
      destination: .healthy,
      actions: [.deriveSessionIdentifiers, .sendSessionReady, .sendCardStatus, .startLiveness]
    ),
    RappRule(
      from: .authenticating,
      event: .handshakeComplete,
      role: .requester,
      destination: .authenticating,
      actions: [.deriveSessionIdentifiers]
    ),
    RappRule(
      from: .authenticating,
      event: .handshakeCompleteWhileRevoking,
      role: .both,
      destination: .closed,
      actions: [.deriveSessionIdentifiers, .sendClosePairingRevoked, .destroySessionMaterial]
    ),
    RappRule(
      from: .authenticating,
      event: .peerCloseReceived,
      role: .requester,
      destination: .closed,
      actions: [.recordPeerCloseReason, .destroySessionMaterial]
    ),
    RappRule(
      from: .authenticating,
      event: .readyVerified,
      role: .requester,
      condition: .readyParametersMatch,
      destination: .healthy,
      actions: [.startLiveness, .showConnected]
    ),
    RappRule(
      from: .authenticating,
      event: .candidateFailure,
      role: .both,
      destination: .closed,
      actions: [.destroySessionMaterial, .closeCandidate]
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
      actions: [.sendCloseProtocolViolation, .showDisconnecting]
    ),
    RappRule(
      from: .healthy,
      event: .peerSilent,
      role: .both,
      destination: .healthy,
      actions: [.sendLivenessPing]
    ),
    RappRule(
      from: .healthy,
      event: .silenceLimitReached,
      role: .both,
      destination: .closing,
      actions: [.noteCloseNoticeImpossible, .showDisconnecting]
    ),
    RappRule(
      from: .healthy,
      event: .userDisconnect,
      role: .both,
      destination: .closing,
      actions: [.sendCloseUserDisconnect, .showDisconnecting]
    ),
    RappRule(
      from: .healthy,
      event: .localCloseRequested,
      role: .both,
      destination: .closing,
      actions: [.sendCloseNormal, .showDisconnecting]
    ),
    RappRule(
      from: .healthy,
      event: .serviceWithdrawn,
      role: .custodian,
      destination: .closing,
      actions: [.sendCloseServiceWithdrawn, .showDisconnecting]
    ),
    RappRule(
      from: .healthy,
      event: .cardUnavailable,
      role: .custodian,
      destination: .closing,
      actions: [.sendCloseCardUnavailable, .showDisconnecting]
    ),
    RappRule(
      from: .healthy,
      event: .peerCloseReceived,
      role: .both,
      destination: .closing,
      actions: [.recordPeerCloseReason, .showDisconnecting]
    ),
    RappRule(
      from: .healthy,
      event: .transportFailed,
      role: .both,
      destination: .closing,
      actions: [.noteCloseNoticeImpossible, .showDisconnecting]
    ),
    RappRule(
      from: .healthy,
      event: .sessionIntegrityFailed,
      role: .both,
      destination: .closing,
      actions: [.noteCloseNoticeImpossible, .showDisconnecting]
    ),
    RappRule(
      from: .healthy,
      event: .authenticatedProtocolViolation,
      role: .both,
      destination: .closing,
      actions: [.sendCloseProtocolViolation, .showDisconnecting]
    ),
    RappRule(
      from: .healthy,
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
      from: .closing,
      event: .peerCloseReceived,
      role: .both,
      destination: .closing,
      actions: []
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
      actions: [.destroySessionMaterial, .destroyCredentialBuffers, .showConnectionStopped]
    ),
  ]
}
