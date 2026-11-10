// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import AppKit
import CardCore
import Foundation
import Testing

@testable import RefineIDTestHost

@Suite("Localized signing prompts", .serialized)
@MainActor
internal struct ScsPinPromptTests {
  private struct ExpectedLabels {
    let basic: String
    let signature: String
    let sign: String
    let cancel: String
    let loginAction: String
    let signAction: String
    let signingAs: String
  }

  private static func expected(for language: String) -> ExpectedLabels {
    switch language {
    case "fi":
      ExpectedLabels(
        basic: "Sy\u{00F6}t\u{00E4} perustunnusluku 1",
        signature: "Sy\u{00F6}t\u{00E4} allekirjoitustunnusluku 2",
        sign: "Allekirjoita", cancel: "Peruuta",
        loginAction: "Toiminto: Kirjautuminen",
        signAction: "Toiminto: Asiakirjan allekirjoitus",
        signingAs: "Allekirjoittajana: Matti Meik\u{00E4}l\u{00E4}inen")
    case "sv":
      ExpectedLabels(
        basic: "Ange grund PIN 1", signature: "Ange signaturkod 2",
        sign: "Signera", cancel: "Avbryt",
        loginAction: "Åtgärd: Inloggning",
        signAction: "Åtgärd: Dokumentunderskrift",
        signingAs: "Undertecknare: Matti Meikäläinen")
    default:
      ExpectedLabels(
        basic: "Enter Basic PIN 1", signature: "Enter Signature PIN 2",
        sign: "Sign", cancel: "Cancel",
        loginAction: "Action: Log in",
        signAction: "Action: Sign document",
        signingAs: "Signing as: Matti Meikäläinen")
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
      purpose: .qualified,
      signerName: "Matti Meikäläinen",
      bundle: bundle)
    #expect(alert.messageText == expected.signature)
    let basic = ScsPinPrompt.makeAlert(
      role: .pin1,
      origin: "https://dvv.fineid.fi",
      purpose: .authentication,
      signerName: "Matti Meikäläinen",
      bundle: bundle)
    #expect(basic.messageText == expected.basic)
    // The origin, the kind of request, and the signer have to be in
    // the prompt: the specification requires the origin (v1.3 §2.1),
    // and the action plus the name is the context a holder can act
    // on. No digest hex: nothing compares against it.
    #expect(
      alert.informativeText
        == "Origin: https://dvv.fineid.fi\n\(expected.signAction)\n\(expected.signingAs)")
    #expect(
      basic.informativeText
        == "Origin: https://dvv.fineid.fi\n\(expected.loginAction)\n\(expected.signingAs)")
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
      purpose: .qualified,
      signerName: "Matti Meikäläinen",
      bundle: .main)
    #expect(details.contains("https://evil.example"))
    #expect(details.contains("Matti Meikäläinen"))
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
      purpose: .authentication,
      signerName: nil,
      bundle: bundle)
    let stated = String(
      localized: "Origin: (none - the request sent no Origin header)", bundle: bundle)
    let action = String(localized: "Action: Log in", bundle: bundle)
    #expect(details == stated + "\n" + action)
  }

  /// An unnamed signer omits its line rather than printing a
  /// placeholder a holder might mistake for a name.
  @Test
  internal func aMissingSignerOmitsItsLine() {
    let details = ScsPinPrompt.consentDetails(
      origin: "https://dvv.fineid.fi",
      purpose: .qualified,
      signerName: nil,
      bundle: .main)
    #expect(!details.contains("Signing as"))
    #expect(details.split(separator: "\n").count == 2)
  }
}
