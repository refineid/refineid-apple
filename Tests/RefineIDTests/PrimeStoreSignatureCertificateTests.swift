// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore

  /// The qualified signature certificate cached in a prime by the first
  /// signature that reads it.
  @Suite(.serialized)
  internal struct PrimeStoreSignatureCertificateTests {
    /// Access number of the primed card.
    private static let primedAccessNumber = "123456"

    /// Access number of some other card.
    private static let otherAccessNumber = "654321"

    /// A synthetic current-card serial.
    private static let chipSerialText = "XA1234567"

    /// Synthetic answer-to-reset text naming the primed card's lookup.
    private static let answerToReset = Data("synthetic answer to reset".utf8)

    private static func primeCard(certificate: Data) throws {
      PrimeStore.forgetAll()
      let identity = try #require(
        PrimedIdentity(
          can: Self.primedAccessNumber,
          certificate: certificate,
          issuer: nil,
          chipSerial: ChipSerial(value: Self.chipSerialText),
          activationCheck: .passed))
      let lookup = try #require(PrimeLookupIdentifier(answerToReset: Self.answerToReset))
      #expect(PrimeStore.store(identity, forLookup: lookup))
    }

    @Test
    internal func certificateIsCachedInThePrimeOfTheCardThatSuppliedIt() throws {
      let chain = try CardAuthorityChainFixtures.make()
      try Self.primeCard(certificate: chain.leaf)
      defer { PrimeStore.forgetAll() }

      #expect(PrimeStore.signatureCertificate(cardAccessNumber: Self.primedAccessNumber) == nil)
      #expect(
        PrimeStore.updateSignatureCertificate(
          chain.issuing, cardAccessNumber: Self.primedAccessNumber))

      #expect(
        PrimeStore.signatureCertificate(cardAccessNumber: Self.primedAccessNumber)
          == chain.issuing)
    }

    @Test
    internal func certificateFromAnotherCardIsNotCached() throws {
      let chain = try CardAuthorityChainFixtures.make()
      try Self.primeCard(certificate: chain.leaf)
      defer { PrimeStore.forgetAll() }

      #expect(
        !PrimeStore.updateSignatureCertificate(
          chain.issuing, cardAccessNumber: Self.otherAccessNumber))

      #expect(PrimeStore.signatureCertificate(cardAccessNumber: Self.primedAccessNumber) == nil)
      #expect(PrimeStore.signatureCertificate(cardAccessNumber: Self.otherAccessNumber) == nil)
    }
  }

#endif
