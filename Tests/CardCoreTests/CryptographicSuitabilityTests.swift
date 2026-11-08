// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore

  /// The suitability table reproduces EU DSS 6.5.1's default policy, and
  /// an archive timestamp is valid until the earliest of its chain's
  /// notAfter and its algorithm's end.
  @Suite
  internal struct CryptographicSuitabilityTests {
    private static let rsa2048 = 2_048
    private static let rsa3072 = 3_072
    private static let rsa4096 = 4_096
    private static let rsa1024 = 1_024
    private static let rsa512 = 512
    private static let p256 = 256
    private static let p384 = 384
    private static let p521 = 521

    /// 2035-01-01T00:00:00Z, the NotAfter DVV's validator reports for
    /// an RSA-SHA384 timestamp by a 4096-bit authority key
    /// (`<SecureAlgorithm>true</SecureAlgorithm>`).
    private static let dvvReference = "2035-01-01T00:00:00Z"
    private static let rsa1900End = "2027-01-01T00:00:00Z"
    private static let rsa1536End = "2019-10-01T00:00:00Z"
    private static let chainEnd = "2030-01-01T00:00:00Z"

    private static func instant(_ text: String) throws -> Date {
      try #require(ISO8601DateFormatter().date(from: text))
    }

    private static func verdict(
      _ family: CryptographicSuitability.Family,
      _ bits: Int,
      _ digest: TimestampCmsVerifier.Digest
    ) -> CryptographicSuitability.Verdict {
      CryptographicSuitability.verdict(
        for: CryptographicSuitability.Key(family: family, bits: bits), digest: digest)
    }

    /// DVV's report for an RSA-SHA384 timestamp: secure, NotAfter
    /// 2035-01-01T00:00:00Z.
    @Test
    internal func theDvvReferenceRowIsReproduced() throws {
      #expect(
        Self.verdict(.rsa, Self.rsa4096, .sha384) == .until(try Self.instant(Self.dvvReference)))
      #expect(
        Self.verdict(.rsa, Self.rsa3072, .sha384) == .until(try Self.instant(Self.dvvReference)))
    }

    /// The pinned rows: RSA from 1900 bits ends 2027, below it 2019, and
    /// below 786 bits it is not acceptable; ECDSA from 256 bits and the
    /// SHA-2 digests do not expire.
    @Test
    internal func thePinnedRows() throws {
      #expect(
        Self.verdict(.rsa, Self.rsa2048, .sha256) == .until(try Self.instant(Self.rsa1900End)))
      #expect(
        Self.verdict(.rsa, Self.rsa1024, .sha512) == .until(try Self.instant(Self.rsa1536End)))
      #expect(Self.verdict(.rsa, Self.rsa512, .sha256) == .unacceptable)
      for bits in [Self.p256, Self.p384, Self.p521] {
        for digest in [TimestampCmsVerifier.Digest.sha256, .sha384, .sha512] {
          #expect(Self.verdict(.ecdsa, bits, digest) == .unlimited)
        }
      }
    }

    /// The date is the earliest of the chain's notAfter and the
    /// algorithm's end, whichever comes first.
    @Test
    internal func theDateIsTheEarliestOfChainAndAlgorithm() throws {
      let chain = try Self.instant(Self.chainEnd)
      let rsaEnd = try Self.instant(Self.rsa1900End)
      let later = try Self.instant(Self.dvvReference)

      #expect(
        TimestampJudge.validUntil(chainEnds: [later, chain], suitability: .until(rsaEnd)) == rsaEnd)
      #expect(
        TimestampJudge.validUntil(chainEnds: [later, chain], suitability: .until(later)) == chain)
      #expect(
        TimestampJudge.validUntil(chainEnds: [later, chain], suitability: .unlimited) == chain)
      #expect(
        TimestampJudge.validUntil(chainEnds: [chain], suitability: .unacceptable) == .distantPast)
    }

    /// An empty chain or a notAfter that does not read leaves no date,
    /// never a later one.
    @Test
    internal func anUnknownEndLeavesNoDate() throws {
      let chain = try Self.instant(Self.chainEnd)
      #expect(TimestampJudge.validUntil(chainEnds: [chain, nil], suitability: .unlimited) == nil)
      #expect(TimestampJudge.validUntil(chainEnds: [], suitability: .unlimited) == nil)
    }

    /// The archive timestamp that counts is the last in document order,
    /// whatever times the clocks name.
    @Test
    internal func theLastArchiveTimestampInDocumentOrderCounts() throws {
      let laterClock = try Self.instant(Self.dvvReference)
      let earlierClock = try Self.instant(Self.chainEnd)
      let first = DocumentVerification.ArchiveCandidate(
        state: .anchored(laterClock), covered: nil, validUntil: laterClock)
      let last = DocumentVerification.ArchiveCandidate(
        state: .anchored(earlierClock), covered: nil, validUntil: earlierClock)
      let unproven = DocumentVerification.ArchiveCandidate(
        state: .invalid, covered: nil, validUntil: nil)

      #expect(
        DocumentVerification.LongTermJudgement.validUntil(of: [first, last, unproven])
          == earlierClock)
    }
  }

#endif
