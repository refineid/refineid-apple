// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation

  /// Which document controls the Mac window shows.
  ///
  /// Signing is offered while a card or a paired phone can sign, or a
  /// signature is in flight. Without one the window is for verifying
  /// only: the drop area invites verification, nothing about signing is
  /// shown, and once a document is listed the identity row that asks
  /// for a reader steps aside. The button bar below every panel holds
  /// Verify, enabled while documents are listed and no signature runs,
  /// and Sign while signing is offered.
  internal struct StatusDocumentControls: Equatable {
    /// One button of the window's button bar.
    internal enum Action: Equatable, Hashable {
      case sign
      case verify
    }

    /// Whether the identity row is shown.
    internal let showsIdentity: Bool

    /// Whether the signing panel is shown and the drop area invites
    /// signing as well as verifying.
    internal let offersSigning: Bool

    /// Whether the Verify button can run.
    internal let verifyEnabled: Bool

    /// Whether a failure waits in the status row to be read: Sign is
    /// held back and "OK" takes the default action until it is.
    internal let awaitsAcknowledgement: Bool

    /// Whether there is anything for the buttons to act on: a listed
    /// document, or a signature or card read under way.
    internal let hasWork: Bool

    /// The button bar, left to right: Verify, then the default Sign.
    ///
    /// Sign is there while signing is offered. The bar is empty while
    /// nothing is listed, since neither button could do anything then.
    internal var actions: [Action] {
      guard hasWork else { return [] }
      return offersSigning ? [.verify, .sign] : [.verify]
    }

    /// The controls for the window's state.
    ///
    /// A signature or a card read
    /// in flight keeps the signing panel through a momentary loss of
    /// the card's publication.
    internal init(
      availability: LoginIdentityModel.Availability,
      queued: [URL],
      signing working: Bool,
      readingCard readingStamp: Bool,
      failureShown: Bool
    ) {
      offersSigning = availability != .noCard || working || readingStamp
      showsIdentity = offersSigning || queued.isEmpty
      verifyEnabled = QueuedDocumentVerification.isAvailable(queued: queued, signing: working)
      awaitsAcknowledgement = failureShown
      hasWork = !queued.isEmpty || working || readingStamp
    }

    /// Whether Sign can run, given that the card side is ready.
    internal func allowsSigning(cardReady: Bool) -> Bool {
      cardReady && offersSigning && !awaitsAcknowledgement
    }
  }

#endif
