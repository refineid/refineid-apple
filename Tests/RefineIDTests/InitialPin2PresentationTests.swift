// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Testing

@testable import RefineIDTestHost

@MainActor
internal struct InitialPin2PresentationTests {
  @Test
  internal func credentialRetryHealthKeyHighlightsInitialPin2UnlessCriticalOrClosed() {
    #expect(
      CredentialRetryHealthKey.showsPin2ChangeWarning(
        level: .pristine, routeAvailable: true, pin2RequiresChange: true
      )
    )
    #expect(
      CredentialRetryHealthKey.showsPin2ChangeWarning(
        level: .warning, routeAvailable: true, pin2RequiresChange: true
      )
    )
    #expect(
      CredentialRetryHealthKey.showsPin2ChangeWarning(
        level: nil, routeAvailable: true, pin2RequiresChange: true
      )
    )
    #expect(
      !CredentialRetryHealthKey.showsPin2ChangeWarning(
        level: .pristine, routeAvailable: true, pin2RequiresChange: false
      )
    )
    // Critical red recovery takes precedence over orange initial-PIN-2 notice.
    #expect(
      !CredentialRetryHealthKey.showsPin2ChangeWarning(
        level: .critical, routeAvailable: true, pin2RequiresChange: true
      )
    )
    // A closed route never shows the warning.
    #expect(
      !CredentialRetryHealthKey.showsPin2ChangeWarning(
        level: .pristine, routeAvailable: false, pin2RequiresChange: true
      )
    )
  }

  @Test
  internal func credentialRetryHealthKeyAccessibilityValuePreservesWarningDetails() {
    let expectedPin2Notice = String(localized: "Change PIN 2 so you can sign documents.")
    #expect(
      CredentialRetryHealthKey.accessibilityValueText(
        level: .pristine, showsPin2ChangeWarning: true
      ) == expectedPin2Notice
    )
    // Warning-level retry state is preserved alongside the initial-PIN-2 notice for VoiceOver.
    #expect(
      CredentialRetryHealthKey.accessibilityValueText(
        level: .warning, showsPin2ChangeWarning: true
      ) == "\(CredentialRetryHealth.Level.warning.accessibilityValue). \(expectedPin2Notice)"
    )
    #expect(
      CredentialRetryHealthKey.accessibilityValueText(
        level: .critical, showsPin2ChangeWarning: false
      ) == CredentialRetryHealth.Level.critical.accessibilityValue
    )
  }

  #if os(iOS)
    @Test
    internal func iosHomeHidesSignAndShowsInitialPin2NoticeForLocalCard() {
      #expect(
        CardCredentialsView.isSigningBlockedByInitialPin2(
          hasLocalIdentity: true, usesRemoteSigning: false, pin2RequiresChangeBeforeSigning: true
        )
      )
      #expect(
        !CardCredentialsView.isSigningAvailable(
          hasLocalIdentity: true, hasRemoteSigningIdentity: false,
          usesRemoteSigning: false, pin2RequiresChangeBeforeSigning: true
        )
      )
      // When a local card overrides a paired remote card, the blocked local card still blocks Sign.
      #expect(
        !CardCredentialsView.isSigningAvailable(
          hasLocalIdentity: true, hasRemoteSigningIdentity: true,
          usesRemoteSigning: false, pin2RequiresChangeBeforeSigning: true
        )
      )
      #expect(
        !CardCredentialsView.isSigningBlockedByInitialPin2(
          hasLocalIdentity: true, usesRemoteSigning: false, pin2RequiresChangeBeforeSigning: false
        )
      )
      #expect(
        CardCredentialsView.isSigningAvailable(
          hasLocalIdentity: true, hasRemoteSigningIdentity: false,
          usesRemoteSigning: false, pin2RequiresChangeBeforeSigning: false
        )
      )
    }

    @Test
    internal func iosHomeKeepsRemoteSigningAvailableAndHidesNoticeWithoutIdentity() {
      // Without any identity, the signing section remains hidden even if the flag is set.
      #expect(
        !CardCredentialsView.isSigningBlockedByInitialPin2(
          hasLocalIdentity: false, usesRemoteSigning: false, pin2RequiresChangeBeforeSigning: true
        )
      )
      #expect(
        !CardCredentialsView.isSigningAvailable(
          hasLocalIdentity: false, hasRemoteSigningIdentity: false,
          usesRemoteSigning: false, pin2RequiresChangeBeforeSigning: true
        )
      )
      // Remote signing remains available when RAPP remote signing is the active signing route.
      #expect(
        !CardCredentialsView.isSigningBlockedByInitialPin2(
          hasLocalIdentity: false, usesRemoteSigning: true, pin2RequiresChangeBeforeSigning: true
        )
      )
      #expect(
        CardCredentialsView.isSigningAvailable(
          hasLocalIdentity: false, hasRemoteSigningIdentity: true,
          usesRemoteSigning: true, pin2RequiresChangeBeforeSigning: true
        )
      )
    }

    @Test
    internal func documentSigningOnlyMarksLocalHealthOnLocalPin2ChangeRequired() {
      #expect(
        DocumentSigningView.shouldMarkLocalInitialPin2(
          usesRappSigning: false, error: DocumentSigner.Failure.card(.pin2ChangeRequired)
        )
      )
      #expect(
        !DocumentSigningView.shouldMarkLocalInitialPin2(
          usesRappSigning: true, error: DocumentSigner.Failure.card(.pin2ChangeRequired)
        )
      )
      #expect(
        !DocumentSigningView.shouldMarkLocalInitialPin2(
          usesRappSigning: false, error: DocumentSigner.Failure.card(.pinBlocked)
        )
      )
    }
  #endif
}
