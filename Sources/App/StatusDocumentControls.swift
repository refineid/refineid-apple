// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import RappRequester

  /// Which document controls the Mac window shows.
  ///
  /// Signing is offered while a card or a paired phone can sign, or a
  /// signature is in flight. When verification is compiled in as well,
  /// the drop area stays open without a card so listed documents can be
  /// verified, and the identity row steps aside while documents wait
  /// without a card; when verification is compiled out, the window
  /// keeps the identity row and hides the empty drop area until a card
  /// can sign.
  internal struct StatusDocumentControls: Equatable {
    /// One button of the window's button bar.
    internal enum Action: Equatable, Hashable {
      case sign
      case verify
    }

    #if FEATURE_DOCUMENT_VERIFICATION
      /// Whether this build compiles document verification in.
      internal static let defaultOffersVerification = true
    #else
      /// Whether this build compiles document verification in.
      internal static let defaultOffersVerification = false
    #endif

    /// Whether the identity row is shown.
    internal let showsIdentity: Bool

    /// Whether the document drop area or waiting pile is shown.
    internal let showsDocuments: Bool

    /// Whether the signing panel is shown and the drop area invites
    /// signing.
    internal let offersSigning: Bool

    /// Whether the window offers document verification.
    internal let offersVerification: Bool

    /// Whether the Verify button can run.
    internal let verifyEnabled: Bool

    /// Whether a failure waits in the status row to be read: Sign is
    /// held back and "OK" takes the default action until it is.
    internal let failureIsVisible: Bool

    /// Whether there is anything for the buttons to act on: a listed
    /// document, or a signature or card read under way.
    internal let hasWork: Bool

    /// The button bar, left to right: Verify when offered, then the
    /// default Sign while signing is offered.
    ///
    /// The bar is empty while nothing is listed, since no button could
    /// do anything then.
    internal var actions: [Action] {
      guard hasWork else { return [] }
      if offersVerification {
        return offersSigning ? [.verify, .sign] : [.verify]
      }
      return offersSigning ? [.sign] : []
    }

    /// The controls for the window's state.
    ///
    /// A signature or a card read
    /// in flight keeps the signing panel through a momentary loss of
    /// the card's publication.
    internal init(
      availability: IdentityAvailability,
      queued: [URL],
      signing working: Bool,
      readingCard readingStamp: Bool,
      failureShown: Bool,
      offersVerification: Bool
    ) {
      let signingOffered = availability != .noCard || working || readingStamp
      offersSigning = signingOffered
      self.offersVerification = offersVerification
      showsIdentity = !offersVerification || signingOffered || queued.isEmpty
      showsDocuments = offersVerification || signingOffered || !queued.isEmpty
      verifyEnabled =
        offersVerification
        && QueuedDocumentVerification.isAvailable(queued: queued, signing: working)
      failureIsVisible = failureShown
      hasWork = !queued.isEmpty || working || readingStamp
    }

    /// Whether Sign can run, given that the card side is ready.
    internal func allowsSigning(cardReady: Bool) -> Bool {
      cardReady && offersSigning
    }
  }

#endif
