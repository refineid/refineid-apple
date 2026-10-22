// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)
  import Foundation

  /// One authenticated RAPP request awaiting the card holder's decision.
  ///
  /// The digest, PIN 1, CAN, keys, and wire frame are deliberately absent.
  /// SwiftUI receives only bounded display context and an action category.
  internal struct RappAuthorizationRequest: Sendable, Equatable {
    internal enum Action: Sendable, Equatable {
      case browserAuthentication
      case documentSignature
    }

    internal let requestID: String
    internal let requester: String
    internal let action: Action
    internal let displayContext: String?
    /// What the card said about the PIN the holder entered last for this
    /// request, when it refused it (RAPP v26.10.21 §10.2).
    internal let notice: String?

  }
#endif
