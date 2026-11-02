// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Security
  import Testing

  @testable import CardCore
  @testable import RefineIDTestHost

  /// An organization prime kept under an answer to reset with no
  /// historical bytes, as the phone's own antenna reports one.
  @Suite(.serialized)
  internal struct OrganizationPrimeStoreTests {
    /// A synthetic answer to reset that carries no historical bytes.
    private static let antennaAnswer = Data("synthetic antenna answer".utf8)

    /// Another such answer, naming another card model.
    private static let otherAnswer = Data("synthetic other answer".utf8)

    /// A synthetic chip serial.
    private static let serialText = "XA1234567"

    @Test
    internal func anAnswerWithoutHistoricalBytesKeepsItsPrime() throws {
      OrganizationPrimeStore.forgetAll()
      defer { OrganizationPrimeStore.forgetAll() }
      let chain = try CardAuthorityChainFixtures.make()
      let serial = try #require(ChipSerial(value: Self.serialText))
      let prime = try #require(
        OrganizationPrime(
          certificate: chain.leaf, issuer: nil, signatureCertificate: nil, chipSerial: serial))

      #expect(
        OrganizationPrimeStore.store(prime, answerToReset: Self.antennaAnswer) == errSecSuccess)
      #expect(OrganizationPrimeStore.read(answerToReset: Self.antennaAnswer) == prime)
      #expect(OrganizationPrimeStore.read(answerToReset: Self.otherAnswer) == nil)
      #expect(OrganizationPrimeStore.store(prime, answerToReset: Data()) == errSecParam)
    }
  }

#endif
