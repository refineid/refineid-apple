// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Testing

@testable import RefineIDTestHost

@MainActor
@Suite(.serialized, SharedDemoStateScope())
internal struct InitialPin2PresentationTests {
  @Test
  internal func credentialRetryHealthKeyHighlightsInitialPin2UnlessCriticalOrClosed() {
    #expect(
      CredentialRetryHealthKey.showsPin2ChangeWarning(
        level: .pristine,
        routeAvailable: true,
        pin2RequiresChange: true
      )
    )
    #expect(
      CredentialRetryHealthKey.showsPin2ChangeWarning(
        level: .warning,
        routeAvailable: true,
        pin2RequiresChange: true
      )
    )
    #expect(
      CredentialRetryHealthKey.showsPin2ChangeWarning(
        level: nil,
        routeAvailable: true,
        pin2RequiresChange: true
      )
    )
    // Critical red recovery takes precedence over orange initial-PIN-2 notice.
    #expect(
      !CredentialRetryHealthKey.showsPin2ChangeWarning(
        level: .critical,
        routeAvailable: true,
        pin2RequiresChange: true
      )
    )
    // A closed route never shows the warning.
    #expect(
      !CredentialRetryHealthKey.showsPin2ChangeWarning(
        level: .pristine,
        routeAvailable: false,
        pin2RequiresChange: true
      )
    )
    #expect(
      !CredentialRetryHealthKey.accessibilityValue(
        level: .pristine,
        showsPin2ChangeWarning: true
      ).isEmpty
    )
    #expect(
      CredentialRetryHealthKey.accessibilityValue(
        level: .critical,
        showsPin2ChangeWarning: false
      ) == CredentialRetryHealth.Level.critical.accessibilityValue
    )
  }

  #if os(iOS)
    @Test
    internal func iosHomeHidesSignAndShowsInitialPin2NoticeForLocalCard() {
      #expect(
        CardCredentialsView.isSigningBlockedByInitialPin2(
          hasLocalIdentity: true,
          hasRemoteSigningIdentity: false,
          pin2RequiresChangeBeforeSigning: true
        )
      )
      #expect(
        !CardCredentialsView.isSigningAvailable(
          hasLocalIdentity: true,
          hasRemoteSigningIdentity: false,
          pin2RequiresChangeBeforeSigning: true
        )
      )
      #expect(
        !CardCredentialsView.isSigningBlockedByInitialPin2(
          hasLocalIdentity: true,
          hasRemoteSigningIdentity: false,
          pin2RequiresChangeBeforeSigning: false
        )
      )
      #expect(
        CardCredentialsView.isSigningAvailable(
          hasLocalIdentity: true,
          hasRemoteSigningIdentity: false,
          pin2RequiresChangeBeforeSigning: false
        )
      )
      // Remote signing remains available when a paired remote card provides the signing identity.
      #expect(
        !CardCredentialsView.isSigningBlockedByInitialPin2(
          hasLocalIdentity: false,
          hasRemoteSigningIdentity: true,
          pin2RequiresChangeBeforeSigning: true
        )
      )
      #expect(
        CardCredentialsView.isSigningAvailable(
          hasLocalIdentity: false,
          hasRemoteSigningIdentity: true,
          pin2RequiresChangeBeforeSigning: true
        )
      )
    }
  #endif
}
