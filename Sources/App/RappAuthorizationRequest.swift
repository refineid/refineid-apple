// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)
  import Foundation

  /// One authenticated RAPP request awaiting the card holder's decision.
  ///
  /// The digest, PIN 1, CAN, keys, and wire frame are deliberately absent.
  /// SwiftUI receives only the requesting computer's name, the documents a
  /// signature names, and an action category.
  internal struct RappAuthorizationRequest: Sendable, Equatable {
    internal enum Action: Sendable, Equatable {
      case browserAuthentication
      case documentSignature
    }

    internal let requestID: String
    internal let requester: String
    internal let action: Action
    /// The documents a signature names, in signing order; empty for an
    /// authentication, which names only the computer (§11 item 1).
    internal let documentNames: [String]
    /// What the card said about the PIN the holder entered last for this
    /// request, when it refused it (RAPP v26.10.22 §10.2).
    internal let notice: String?

    /// The prompt's title, naming the act.
    internal var title: String {
      switch action {
      case .browserAuthentication:
        RappAuthorizationPrompt.authenticationTitle

      case .documentSignature:
        RappAuthorizationPrompt.signatureTitle
      }
    }

    /// The prompt's one sentence, naming the computer and the documents.
    internal var message: String {
      switch action {
      case .browserAuthentication:
        RappAuthorizationPrompt.authenticationMessage(computer: requester)

      case .documentSignature:
        RappAuthorizationPrompt.signatureMessage(computer: requester, documents: documentNames)
      }
    }
  }
#endif
