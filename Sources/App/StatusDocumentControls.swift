// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation

  /// Which document controls the Mac window shows.
  ///
  /// Signing is offered while a card or a paired phone can sign, or a
  /// signature is in flight. Without one the window is for verifying
  /// only: the drop area invites verification, nothing about signing is
  /// shown, and once a document is listed the identity row that asks
  /// for a reader steps aside. Verify sits below everything, enabled
  /// while documents are listed and no signature runs.
  internal struct StatusDocumentControls: Equatable {
    /// Whether the identity row is shown.
    internal let showsIdentity: Bool

    /// Whether the signing panel is shown and the drop area invites
    /// signing as well as verifying.
    internal let offersSigning: Bool

    /// Whether the Verify button can run.
    internal let verifyEnabled: Bool

    internal init(
      availability: LoginIdentityModel.Availability,
      queued: [URL],
      signing working: Bool
    ) {
      offersSigning = availability != .noCard || working
      showsIdentity = offersSigning || queued.isEmpty
      verifyEnabled = QueuedDocumentVerification.isAvailable(queued: queued, signing: working)
    }
  }

#endif
