// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Foundation
  import Testing

  @testable import RefineID

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
      let compact = try TimestampClient.verifiedCompactEncoding(Self.token)

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
        changed[last] ^= 1
      }

      #expect(throws: TimestampTokenVerifier.Failure.invalidSignature) {
        _ = try TimestampClient.verifiedCompactEncoding(changed)
      }
    }

    /// Temporary refusal backs off to one minute and keeps trying.
    @Test
    internal func transientFailureRetriesUntilSuccess() async throws {
      var attempts = 0
      var delays: [Duration] = []

      let answer = try await TimestampClient.withTransientRetry {
        attempts += 1
        if attempts <= 8 {
          throw SigningNetwork.Failure.httpStatus(429)
        }
        return "timestamp"
      } wait: { delay in
        delays.append(delay)
      }

      #expect(answer == "timestamp")
      #expect(attempts == 9)
      #expect(
        delays == [1, 2, 4, 8, 16, 32, 60, 60].map { .seconds($0) }
      )
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
  }

#endif
