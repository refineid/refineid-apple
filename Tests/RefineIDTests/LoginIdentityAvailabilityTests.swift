// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Testing

  @testable import RefineID

  /// The login row names a person only when a card or a holder is here.
  @Suite
  internal struct LoginIdentityAvailabilityTests {
    @Test
    internal func leftoverTokenWithoutSourceIsNotReady() {
      #expect(
        LoginIdentityModel.resolved(
          tokenPublished: true,
          cardPresent: false,
          holderAdvertising: false,
          hasBorrowedCertificate: true
        ) == .noCard
      )
    }

    @Test
    internal func localCardWithPublishedTokenIsReady() {
      #expect(
        LoginIdentityModel.resolved(
          tokenPublished: true,
          cardPresent: true,
          holderAdvertising: false,
          hasBorrowedCertificate: false
        ) == .ready
      )
    }

    @Test
    internal func advertisingHolderWithCertificateIsReady() {
      #expect(
        LoginIdentityModel.resolved(
          tokenPublished: false,
          cardPresent: false,
          holderAdvertising: true,
          hasBorrowedCertificate: true
        ) == .ready
      )
    }

    @Test
    internal func cardWithoutTokenIsUnready() {
      #expect(
        LoginIdentityModel.resolved(
          tokenPublished: false,
          cardPresent: true,
          holderAdvertising: false,
          hasBorrowedCertificate: false
        ) == .cardWithoutIdentity
      )
    }

    @Test
    internal func advertisingHolderWithoutCertificateIsUnready() {
      #expect(
        LoginIdentityModel.resolved(
          tokenPublished: false,
          cardPresent: false,
          holderAdvertising: true,
          hasBorrowedCertificate: false
        ) == .cardWithoutIdentity
      )
    }

    @Test
    internal func emptySlotWithoutHolderIsNoCard() {
      #expect(
        LoginIdentityModel.resolved(
          tokenPublished: false,
          cardPresent: false,
          holderAdvertising: false,
          hasBorrowedCertificate: false
        ) == .noCard
      )
    }
  }

#endif
