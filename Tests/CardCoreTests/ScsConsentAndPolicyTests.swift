// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Testing

@testable import CardCore

/// Origin validation, display sanitization, SHA-256 consent formatting,
/// per-origin prompt rate limiting, and serial-bound leaf caching.
@Suite
internal struct ScsConsentAndPolicyTests {
  @Test
  internal func originPolicyAdmitsOnlyCleanHttpsWebOrigins() {
    #expect(ScsOriginPolicy.refusal(forPresentOrigin: "https://dvv.fineid.fi") == nil)
    #expect(ScsOriginPolicy.refusal(forPresentOrigin: "https://dvv.fineid.fi:8443") == nil)
    #expect(ScsOriginPolicy.refusal(forPresentOrigin: "https://[::1]:8443") == nil)

    for bad in [
      "http://dvv.fineid.fi",
      "HTTP://dvv.fineid.fi",
      "null",
      "file:///tmp/index.html",
      "https://trusted.fi@evil.example",
      "https://dvv.fineid.fi/path",
      "https://dvv.fineid.fi?query=1",
      "https://dvv.fineid.fi:0",
      "https://dvv.fineid.fi:65536",
      "https://dvv.fineid.fi\u{202E}if.live",
      "https://dvv.fineid.fi\r\nInjected: 1",
    ] {
      #expect(ScsOriginPolicy.refusal(forPresentOrigin: bad) != nil, "accepted \(bad)")
    }
  }

  @Test
  internal func displaySanitizationStripsBidiControlsAndTruncatesLongOrigins() throws {
    let spoof = "https://evil.\u{202E}if.dienif.vvd\r\nAction: Safe"
    let sanitized = try #require(ScsOriginPolicy.sanitizedForDisplay(spoof))
    #expect(!sanitized.contains("\u{202E}"))
    #expect(!sanitized.contains("\n"))
    #expect(!sanitized.contains("\r"))

    let huge = "https://" + String(repeating: "a", count: 200) + ".example"
    let truncated = try #require(ScsOriginPolicy.sanitizedForDisplay(huge))
    #expect(truncated.hasPrefix("https://"))
    #expect(truncated.hasSuffix(".example"))
    #expect(truncated.contains("…"))
    #expect(truncated.count == ScsValues.originDisplayMaximumCharacters)
  }

  @Test
  internal func consentDetailsIncludeExactSha256AndSanitizeSigner() {
    let payload = Data("contract-bytes-to-sign".utf8)
    let request = ScsSignRequest(
      purpose: .qualified,
      hash: .sha256,
      data: payload,
      origin: "https://dvv.fineid.fi"
    )
    let expectedHex = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    #expect(request.sha256Hex == expectedHex)

    let details = ScsConsentDetails.format(
      origin: request.origin,
      purpose: request.purpose,
      signerName: "Matti\n\u{202E}Meikäläinen",
      sha256Hex: request.sha256Hex,
      bundle: .main
    )
    #expect(details.contains(expectedHex))
    #expect(!details.contains("\u{202E}"))
    #expect(details.split(separator: "\n").count == 4)
  }

  @Test
  internal func rateLimiterEnforcesWindowCapAndRefusalCooldown() {
    let limiter = ScsPromptRateLimiter(
      windowSeconds: 60,
      maximumPerWindow: 3,
      refusalCooldownSeconds: 10
    )
    let start = Date()
    let origin = "https://service.example"
    #expect(limiter.checkAndRecordPrompt(origin: origin, at: start) == .allow)
    #expect(limiter.checkAndRecordPrompt(origin: origin, at: start.addingTimeInterval(1)) == .allow)
    #expect(limiter.checkAndRecordPrompt(origin: origin, at: start.addingTimeInterval(2)) == .allow)
    if case .allow = limiter.checkAndRecordPrompt(origin: origin, at: start.addingTimeInterval(3)) {
      Issue.record("expected fourth prompt inside window to be throttled")
    }
    #expect(
      limiter.checkAndRecordPrompt(origin: "https://other.example", at: start.addingTimeInterval(3))
        == .allow
    )
    #expect(
      limiter.checkAndRecordPrompt(origin: origin, at: start.addingTimeInterval(61)) == .allow
    )

    limiter.recordRefusal(origin: origin, at: start.addingTimeInterval(62))
    if case .allow = limiter.checkAndRecordPrompt(origin: origin, at: start.addingTimeInterval(65))
    {
      Issue.record("expected cooldown after refusal")
    }
    #expect(
      limiter.checkAndRecordPrompt(origin: origin, at: start.addingTimeInterval(73)) == .allow
    )
  }

  @Test
  internal func leafCacheInvalidatesOnCardSerialChangeOrRemoval() throws {
    let firstCard = try #require(ChipSerial(value: "0102030405060708"))
    let secondCard = try #require(ChipSerial(value: "AABBCCDDEEFF0011"))
    let leafOne = Data([0x30, 0x01, 0x01])
    let leafTwo = Data([0x30, 0x01, 0x02])

    var cache = ScsLeafCache()
    cache.store(leaf: leafOne, for: .qualified, serial: firstCard)
    #expect(cache.cachedLeaf(for: .qualified, serial: firstCard) == leafOne)
    #expect(cache.cachedLeaf(for: .qualified, serial: secondCard) == nil)
    #expect(cache.cachedLeaf(for: .qualified, serial: firstCard) == nil)

    cache.store(leaf: leafTwo, for: .qualified, serial: secondCard)
    #expect(cache.cachedLeaf(for: .qualified, serial: secondCard) == leafTwo)
    cache.invalidate()
    #expect(cache.cachedLeaf(for: .qualified, serial: secondCard) == nil)
  }
}
