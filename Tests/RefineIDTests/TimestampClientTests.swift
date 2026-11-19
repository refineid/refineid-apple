// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import AppKit
  import CardCore
  import Foundation
  import Testing

  @testable import RefineIDTestHost

  /// Direct checks for the compact timestamp's verify-before-strip boundary.
  @Suite
  internal struct TimestampClientTests {
    /// A valid RFC 3161 token carrying its self-issued test signer.
    private static let token = Self.decode(
      """
      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
      1qOUqQgGIjMZvFY=
      """
    )

    /// The token's exact signer, as embedded in the token itself.
    private static let signer = Self.decode(
      """
      MIIBszCCAVigAwIBAgIUMHfE/GmdSvG3+CQRxHSnFzfP2IwwCgYIKoZIzj0EAwIwHDEaMBgGA1UE
      AwwRUmVGaW5lSUQgVGVzdCBUU0EwHhcNMjYwODA0MDc1MzI1WhcNMzYwODAxMDc1MzI1WjAcMRow
      GAYDVQQDDBFSZUZpbmVJRCBUZXN0IFRTQTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABEma/2Y8
      UqzBdNi9vlLoFQ+WHFW8PCTu67N0kmhjl18Eu0kEjTrtF6y5wF1VXf9ktFdnUJX+Rz6FES49kwG7
      cDujeDB2MB0GA1UdDgQWBBTY+L64mtIcQMUST9Jv2XCaRNeLmzAfBgNVHSMEGDAWgBTY+L64mtIc
      QMUST9Jv2XCaRNeLmzAMBgNVHRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIGwDAWBgNVHSUBAf8EDDAK
      BggrBgEFBQcDCDAKBggqhkjOPQQDAgNJADBGAiEAwvyfmlibx6Pf8KmrY7VfgYwxbr56A80RBza/
      J4cPYlECIQCYsi5iogIH1DrFGEDBDrUrjaanfMOXp8GithjIM97ohg==
      """
    )

    /// The bit flipped in the token's last signature octet to tamper with it.
    private static let signatureTailMask: UInt8 = 1

    /// Base64 fixture text with line breaks ignored.
    private static func decode(_ encoded: String) -> Data {
      Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) ?? Data()
    }

    /// Compactness never changes the RFC 3161 request's certReq = TRUE.
    @Test
    internal func compactRequestAsksForTheSignerCertificate() {
      let request = TimestampClient.compactRequest(
        digest: Data(repeating: 0xA5, count: 48),
        nonceBytes: Data(repeating: 0x5A, count: 32)
      )
      let certificateRequest = DerEncoder.booleanTrue()

      #expect(request.suffix(certificateRequest.count) == certificateRequest)
    }

    /// A full token is authenticated before only its certificates are removed.
    @Test
    internal func verifiedTokenBecomesCertificateFree() throws {
      let compact = try TimestampClient.verifiedCompactEncoding(
        Self.token, trustedCertificates: [Self.signer]
      )

      #expect(CmsCertificates.inside(Self.token).contains(Self.signer))
      #expect(CmsCertificates.inside(compact).isEmpty)
      #expect(compact.count < Self.token.count)
      #expect(
        try RfcTimestamp.generationTime(in: compact)
          == RfcTimestamp.generationTime(in: Self.token)
      )
    }

    /// A token with a changed CMS signature is rejected before compaction.
    @Test
    internal func tamperedTokenIsNeverCompacted() {
      var changed = Self.token
      if let last = changed.indices.last {
        changed[last] ^= Self.signatureTailMask
      }

      #expect(throws: TimestampTokenVerifier.Failure.invalidSignature) {
        _ = try TimestampClient.verifiedCompactEncoding(
          changed, trustedCertificates: [Self.signer]
        )
      }
    }

    /// A token whose signer does not chain to supplied trust anchors is rejected.
    @Test
    internal func unanchoredTokenIsRejectedBeforeCompaction() {
      #expect(throws: TimestampTokenVerifier.Failure.untrustedSigner) {
        _ = try TimestampClient.verifiedCompactEncoding(
          Self.token, trustedCertificates: [Data("foreign-anchor".utf8)]
        )
      }
    }

    /// When test trust anchors are configured, they are resolved.
    @Test
    internal func testTrustAnchorsAreUsedWhenConfigured() async throws {
      let resolver: @Sendable (Date) -> [Data] = { _ in [Self.signer] }
      try await TimestampClient.$anchorResolver.withValue(resolver) {
        let anchors = try await TimestampClient.timeStampingAnchors(at: Date())
        #expect(anchors == [Self.signer])
      }
    }

    /// When test trust anchors are empty, untrustedAuthority is thrown.
    @Test
    internal func emptyAnchorsFailAsUntrustedAuthority() async throws {
      let emptyResolver: @Sendable (Date) -> [Data] = { _ in [] }
      await #expect(throws: TimestampClient.Failure.untrustedAuthority) {
        try await TimestampClient.$anchorResolver.withValue(emptyResolver) {
          _ = try await TimestampClient.timeStampingAnchors(at: Date())
        }
      }
    }

    /// Corrupt token signature is reported as invalidToken rather than untrustedAuthority.
    @Test
    internal func invalidSignatureFailsAsInvalidToken() async {
      var changed = Self.token
      if let last = changed.indices.last {
        changed[last] ^= Self.signatureTailMask
      }
      let resolver: @Sendable (Date) -> [Data] = { _ in [Self.signer] }
      await #expect(
        throws: TimestampClient.Failure.invalidToken(
          TimestampTokenVerifier.Failure.invalidSignature
        )
      ) {
        _ = try await TimestampClient.$anchorResolver.withValue(resolver) {
          try await TimestampClient.verifyToken(changed, acquiredAt: Date())
        }
      }
    }

    /// Temporary refusal backs off and succeeds within the attempt budget.
    @Test
    internal func transientFailureRetriesUntilSuccess() async throws {
      var attempts = 0
      var delays: [Duration] = []

      let answer = try await TimestampClient.withTransientRetry {
        attempts += 1
        if attempts <= 4 {
          throw SigningNetwork.Failure.httpStatus(429)
        }
        return "timestamp"
      } wait: { delay in
        delays.append(delay)
      }

      #expect(answer == "timestamp")
      #expect(attempts == 5)
      #expect(delays == [1, 2, 4, 8].map { .seconds($0) })
    }

    /// A down authority is reported after the attempt budget, not retried forever.
    @Test
    internal func transientFailureGivesUpAfterMaximumAttempts() async {
      var attempts = 0
      var delays: [Duration] = []

      await #expect(throws: SigningNetwork.Failure.httpStatus(503)) {
        _ = try await TimestampClient.withTransientRetry {
          attempts += 1
          throw SigningNetwork.Failure.httpStatus(503)
        } wait: { delay in
          delays.append(delay)
        }
      }

      #expect(attempts == TimestampClient.maximumAuthorityAttempts)
      #expect(delays.count == TimestampClient.maximumAuthorityAttempts - 1)
      #expect(delays == [1, 2, 4, 8].map { .seconds($0) })
    }

    /// The backoff doubles from one second and caps at one minute.
    @Test
    internal func retryDelayCapsAtOneMinute() {
      let schedule = [(1, 1), (2, 2), (3, 4), (4, 8), (5, 16), (6, 32), (7, 60), (100, 60)]
      for (failures, seconds) in schedule {
        #expect(TimestampClient.retryDelay(after: failures) == .seconds(seconds))
      }
    }

    /// Authentication failure is returned without another attempt or wait.
    @Test
    internal func permanentFailureDoesNotRetry() async {
      var attempts = 0
      var waited = false

      await #expect(throws: SigningNetwork.Failure.httpStatus(401)) {
        _ = try await TimestampClient.withTransientRetry {
          attempts += 1
          throw SigningNetwork.Failure.httpStatus(401)
        } wait: { _ in
          waited = true
        }
      }

      #expect(attempts == 1)
      #expect(!waited)
    }

    /// A probe at a refused loopback port fails as unanswered,
    /// without retrying behind the settings Test button.
    @Test
    internal func probeReportsARefusedPortWithoutRetrying() async {
      do {
        try await TimestampClient.probe("http://127.0.0.1:9/tsa")
        Issue.record("A refused port must not answer a probe.")
      } catch let failure as TimestampClient.Failure {
        guard case .authorityDidNotAnswer = failure else {
          Issue.record("Wrong failure for a refused port.")
          return
        }
      } catch {
        Issue.record("Unexpected probe error.")
      }
    }

    /// A probe without a connection blames the connection, not the authority.
    @Test
    internal func probeFailureNamesAMissingConnection() {
      #expect(
        TimestampClient.probeFailure(from: URLError(.notConnectedToInternet))
          == TimestampClient.Failure.noNetworkConnection
      )
      #expect(
        TimestampClient.probeFailure(from: URLError(.networkConnectionLost))
          == TimestampClient.Failure.noNetworkConnection
      )
    }

    /// A probe a transport error stops blames the authority.
    @Test
    internal func probeFailureNamesASilentAuthority() {
      for error: Error in [
        URLError(.timedOut),
        URLError(.cannotFindHost),
        NSError(domain: "TimestampClientTests", code: 1),
      ] {
        guard case .authorityDidNotAnswer(let detail) = TimestampClient.probeFailure(from: error)
        else {
          Issue.record("A transport error must read as unanswered.")
          return
        }
        #expect(!detail.isEmpty)
      }
    }

    /// Every failure names its settings badge.
    @Test
    internal func everyFailureNamesASettingsBadge() {
      let badges: [(TimestampClient.Failure, String)] = [
        (.authorityDeclined, TimestampClient.Failure.unansweredBadgeSymbol),
        (.authorityDidNotAnswer("refused"), TimestampClient.Failure.unansweredBadgeSymbol),
        (.noNetworkConnection, TimestampClient.Failure.offlineBadgeSymbol),
        (.invalidResponse(.malformed), TimestampClient.Failure.unclearBadgeSymbol),
        (.invalidToken(.untrustedSigner), TimestampClient.Failure.unclearBadgeSymbol),
        (.randomUnavailable, TimestampClient.Failure.unclearBadgeSymbol),
        (.trustedListsUnavailable, TimestampClient.Failure.unclearBadgeSymbol),
        (.untrustedAuthority, TimestampClient.Failure.unclearBadgeSymbol),
      ]
      for (failure, badge) in badges {
        #expect(failure.badgeSymbol == badge)
      }
    }

    /// The settings badges name real symbols.
    @Test
    internal func settingsBadgesExist() {
      for symbol in [
        TimestampClient.Failure.verifiedBadgeSymbol,
        TimestampClient.Failure.unansweredBadgeSymbol,
        TimestampClient.Failure.offlineBadgeSymbol,
        TimestampClient.Failure.unclearBadgeSymbol,
      ] {
        #expect(
          NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil,
          Comment(rawValue: symbol)
        )
      }
    }
  }

#endif
