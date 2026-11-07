// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)
  import Foundation

  /// The lock-screen notice of one credential action waiting for the unlock.
  internal struct RappUnlockWait: Sendable, Equatable {
    /// The prompt identifier of the operation that waits.
    internal let requestID: String
    /// The computer that asks.
    internal let requester: String
    /// What it asks for.
    internal let action: RappAuthorizationRequest.Action

    /// The sentence naming the computer and the PIN (RAPP v26.11.2 §8.2
    /// item 3); documents stay off the lock screen.
    internal var message: String {
      switch action {
      case .browserAuthentication:
        RappAuthorizationPrompt.unlockAuthenticationMessage(computer: requester)

      case .documentSignature:
        RappAuthorizationPrompt.unlockSignatureMessage(computer: requester)
      }
    }
  }
#endif
