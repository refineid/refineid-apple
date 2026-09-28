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
      case shareCardInformation
    }

    internal let requestID: String
    internal let requester: String
    internal let action: Action
    internal let displayContext: String?

    internal init(
      requestID: String,
      requester: String,
      action: Action
    ) {
      self.init(requestID: requestID, requester: requester, action: action, displayContext: nil)
    }

    internal init(
      requestID: String,
      requester: String,
      action: Action,
      displayContext: String?
    ) {
      self.requestID = requestID
      self.requester = requester
      self.action = action
      self.displayContext = displayContext
    }
  }
#endif
