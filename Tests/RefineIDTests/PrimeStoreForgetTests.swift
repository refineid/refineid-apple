// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore

  /// Forgetting one card by its chip serial.
  @Suite(.serialized)
  internal struct PrimeStoreForgetTests {
    /// Access number of the forgotten card.
    private static let forgottenAccessNumber = "123456"

    /// Access number of the card that stays.
    private static let keptAccessNumber = "654321"

    /// Synthetic chip serial of the forgotten card.
    private static let forgottenSerialText = "XA1234567"

    /// Synthetic chip serial of the card that stays.
    private static let keptSerialText = "XB7654321"

    /// Synthetic answer-to-reset texts naming each record's lookup.
    private static let forgottenAnswerToReset = Data("synthetic forgotten card".utf8)
    private static let keptAnswerToReset = Data("synthetic kept card".utf8)
    private static let undecodableAnswerToReset = Data("synthetic undecodable record".utf8)

    /// Bytes that do not decode into a prime.
    private static let undecodablePayload = Data("not a prime".utf8)

    private static func prime(
      accessNumber: String,
      serialText: String,
      answerToReset: Data,
      certificate: Data
    ) throws -> PrimeLookupIdentifier {
      let serial = try #require(ChipSerial(value: serialText))
      let identity = try #require(
        PrimedIdentity(
          can: accessNumber,
          certificate: certificate,
          issuer: nil,
          chipSerial: serial,
          activationCheck: .passed))
      let lookup = try #require(PrimeLookupIdentifier(answerToReset: answerToReset))
      #expect(PrimeStore.store(identity, forLookup: lookup))
      return lookup
    }

    @Test
    internal func forgettingACardRemovesItsPrimesAndUndecodableRecordsOnly() throws {
      PrimeStore.forgetAll()
      defer { PrimeStore.forgetAll() }
      let chain = try CardAuthorityChainFixtures.make()
      let forgotten = try Self.prime(
        accessNumber: Self.forgottenAccessNumber,
        serialText: Self.forgottenSerialText,
        answerToReset: Self.forgottenAnswerToReset,
        certificate: chain.leaf)
      let kept = try Self.prime(
        accessNumber: Self.keptAccessNumber,
        serialText: Self.keptSerialText,
        answerToReset: Self.keptAnswerToReset,
        certificate: chain.leaf)
      let undecodable = try #require(
        PrimeLookupIdentifier(answerToReset: Self.undecodableAnswerToReset))
      TestCredentialEnvironment.storePrime(Self.undecodablePayload, account: undecodable.value)

      PrimeStore.forget(serial: try #require(ChipSerial(value: Self.forgottenSerialText)))

      #expect(PrimeStore.read(lookupID: forgotten) == nil)
      #expect(PrimeStore.readData(account: undecodable.value) == nil)
      #expect(PrimeStore.read(lookupID: kept)?.can == Self.keptAccessNumber)
    }
  }

#endif
