// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import AppKit
import CardCore
import Foundation
import Testing

@testable import RefineID

@Suite("Localized signing prompts", .serialized)
@MainActor
internal struct ScsPinPromptTests {
  private struct ExpectedLabels {
    let basic: String
    let signature: String
    let sign: String
    let cancel: String
    let digestLine: String
  }

  /// The digest the consent details are expected to print for a known
  /// input, grouped four bytes at a time.
  private static let printedDigest = "00112233 44556677"

  private static let digestInput = Data([
    0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
  ])

  private static func expected(for language: String) -> ExpectedLabels {
    switch language {
    case "fi":
      ExpectedLabels(
        basic: "Sy\u{00F6}t\u{00E4} Perus (PIN 1)",
        signature: "Sy\u{00F6}t\u{00E4} Allekirjoitus (PIN 2)",
        sign: "Allekirjoita", cancel: "Peruuta",
        digestLine: "Tiiviste (SHA256): \(printedDigest)")
    case "sv":
      ExpectedLabels(
        basic: "Ange Bas (PIN 1)", signature: "Ange Signaturkoden (PIN 2)",
        sign: "Signera", cancel: "Avbryt",
        digestLine: "Digest (SHA256): \(printedDigest)")
    default:
      ExpectedLabels(
        basic: "Enter Basic (PIN 1)", signature: "Enter Signature (PIN 2)",
        sign: "Sign", cancel: "Cancel",
        digestLine: "Digest (SHA256): \(printedDigest)")
    }
  }

  @Test(arguments: ["en", "fi", "sv"])
  internal func localizedPrompt(language: String) async throws {
    let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
    let bundle = try #require(Bundle(path: path))
    let expected = Self.expected(for: language)
    let alert = ScsPinPrompt.makeAlert(
      role: .pin2,
      origin: "https://dvv.fineid.fi",
      digest: Self.digestInput,
      hash: .sha256,
      bundle: bundle)
    #expect(alert.messageText == expected.signature)
    let basic = ScsPinPrompt.makeAlert(
      role: .pin1,
      origin: "https://dvv.fineid.fi",
      digest: Self.digestInput,
      hash: .sha256,
      bundle: bundle)
    #expect(basic.messageText == expected.basic)
    // The origin and the digest have to be in the prompt: the
    // specification requires the origin (v1.3 §2.1), and a holder
    // cannot otherwise tell their own document from someone else's.
    #expect(alert.informativeText == "Origin: https://dvv.fineid.fi\n\(expected.digestLine)")
    #expect(alert.buttons.map(\.title) == [expected.sign, expected.cancel])
    #expect(alert.accessoryView is NSSecureTextField)
    let window = NSWindow(
      contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let response = await withCheckedContinuation { continuation in
      alert.beginSheetModal(for: window) { response in
        continuation.resume(returning: response)
      }
      DispatchQueue.main.async {
        alert.buttons.last?.performClick(nil)
      }
    }
    #expect(response == .alertSecondButtonReturn)
  }

  @Test
  internal func consentDetailsNameTheRequestingOrigin() {
    let details = ScsPinPrompt.consentDetails(
      origin: "https://evil.example",
      digest: Self.digestInput,
      hash: .sha256,
      bundle: .main)
    #expect(details.contains("https://evil.example"))
    #expect(details.contains(Self.printedDigest))
  }

  /// A request with no Origin is not a browser page.
  ///
  /// The holder has to be able to see that rather than read a blank
  /// line. The expectation comes from the same bundle rather than a
  /// hard-coded language, so it holds wherever the host is set.
  @Test
  internal func aMissingOriginIsStatedNotBlanked() {
    let bundle = Bundle.main
    let details = ScsPinPrompt.consentDetails(
      origin: nil,
      digest: Self.digestInput,
      hash: .sha256,
      bundle: bundle)
    let stated = String(
      localized: "Origin: (none - the request sent no Origin header)", bundle: bundle)
    #expect(
      details == stated + "\n" + digestLine(hash: .sha256, digest: Self.digestInput))
  }

  /// The printed digest names the hash that produced it, so a holder
  /// comparing two prompts is not comparing unlike digests.
  @Test(arguments: [
    (SigningHash.sha256, "SHA256"),
    (SigningHash.sha384, "SHA384"),
    (SigningHash.sha512, "SHA512"),
  ])
  internal func thePrintedDigestNamesItsHash(hash: SigningHash, name: String) {
    let details = ScsPinPrompt.consentDetails(
      origin: "https://dvv.fineid.fi",
      digest: Data(repeating: 0xab, count: hash.digestByteCount),
      hash: hash,
      bundle: .main)
    #expect(details.contains(name))
  }

  /// A digest longer than one group has to stay grouped and complete,
  /// so the holder can read it against a known value.
  @Test
  internal func aLongDigestKeepsEveryGroup() {
    let digest = Data(repeating: 0xff, count: 32)
    let details = ScsPinPrompt.consentDetails(
      origin: "https://dvv.fineid.fi",
      digest: digest,
      hash: .sha256,
      bundle: .main)
    #expect(details.contains((0..<8).map { _ in "ffffffff" }.joined(separator: " ")))
    #expect(details.hasSuffix(digestLine(hash: .sha256, digest: digest)))
  }

  /// The digest line as the host's language renders it.
  private func digestLine(hash: SigningHash, digest: Data) -> String {
    let details = ScsPinPrompt.consentDetails(
      origin: "unused", digest: digest, hash: hash, bundle: .main)
    return details.split(separator: "\n", maxSplits: 1).last.map(String.init) ?? ""
  }
}
