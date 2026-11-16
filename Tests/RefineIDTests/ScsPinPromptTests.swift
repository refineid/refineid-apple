// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)
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
      let logIn: String
      let cancel: String
      let loginAction: String
      let signAction: String
      let loggingInAs: String
      let signingAs: String
      let digestPrefix: String
    }

    private static let sampleDigest = String(repeating: "a1b2c3d4", count: 8)

    private static func expected(for language: String) -> ExpectedLabels {
      switch language {
      case "fi":
        ExpectedLabels(
          basic: "Syötä perustunnusluku 1",
          signature: "Syötä allekirjoitustunnusluku 2",
          sign: "Allekirjoita",
          logIn: "Kirjaudu",
          cancel: "Peruuta",
          loginAction: "Toiminto: Kirjautuminen",
          signAction: "Toiminto: Asiakirjan allekirjoitus",
          loggingInAs: "Kirjautujana: Matti Meikäläinen",
          signingAs: "Allekirjoittajana: Matti Meikäläinen",
          digestPrefix: "Tiiviste (SHA-256): "
        )
      case "sv":
        ExpectedLabels(
          basic: "Ange grund PIN 1",
          signature: "Ange signaturkod 2",
          sign: "Underteckna",
          logIn: "Logga in",
          cancel: "Avbryt",
          loginAction: "Åtgärd: Inloggning",
          signAction: "Åtgärd: Dokumentunderskrift",
          loggingInAs: "Loggar in som: Matti Meikäläinen",
          signingAs: "Undertecknare: Matti Meikäläinen",
          digestPrefix: "Kontrollsumma (SHA-256): "
        )
      default:
        ExpectedLabels(
          basic: "Enter Basic PIN 1",
          signature: "Enter Signature PIN 2",
          sign: "Sign",
          logIn: "Log in",
          cancel: "Cancel",
          loginAction: "Action: Log in",
          signAction: "Action: Sign document",
          loggingInAs: "Logging in as: Matti Meikäläinen",
          signingAs: "Signing as: Matti Meikäläinen",
          digestPrefix: "Digest (SHA-256): "
        )
      }
    }

    @Test(arguments: ["en", "fi", "sv"])
    internal func localizedConsentDetailsAndTitles(language: String) throws {
      let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
      let bundle = try #require(Bundle(path: path))
      let expected = Self.expected(for: language)

      let signDetails = ScsConsentDetails.format(
        origin: "https://dvv.fineid.fi",
        purpose: .qualified,
        signerName: "Matti Meikäläinen",
        sha256Hex: Self.sampleDigest,
        bundle: bundle
      )
      let loginDetails = ScsConsentDetails.format(
        origin: "https://dvv.fineid.fi",
        purpose: .authentication,
        signerName: "Matti Meikäläinen",
        sha256Hex: Self.sampleDigest,
        bundle: bundle
      )
      #expect(
        signDetails
          == "Origin: https://dvv.fineid.fi\n\(expected.signAction)\n\(expected.signingAs)\n"
          + "\(expected.digestPrefix)\(Self.sampleDigest)"
      )
      #expect(
        loginDetails
          == "Origin: https://dvv.fineid.fi\n\(expected.loginAction)\n\(expected.loggingInAs)\n"
          + "\(expected.digestPrefix)\(Self.sampleDigest)"
      )
      #expect(ScsConsentDetails.confirmTitle(purpose: .qualified, bundle: bundle) == expected.sign)
      #expect(
        ScsConsentDetails.confirmTitle(purpose: .authentication, bundle: bundle) == expected.logIn)
      #expect(CredentialLabels.entryPrompt(for: .pin2, bundle: bundle) == expected.signature)
      #expect(CredentialLabels.entryPrompt(for: .pin1, bundle: bundle) == expected.basic)
    }

    #if FEATURE_SCS
      @Test(arguments: ["en", "fi", "sv"])
      internal func localizedAlertPresentsSecureFieldAndCancelsSheet(
        language: String
      ) async throws {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        let expected = Self.expected(for: language)
        let context = ScsPinPrompt.Context(
          role: .pin2,
          origin: "https://dvv.fineid.fi",
          purpose: .qualified,
          signerName: "Matti Meikäläinen",
          sha256Hex: Self.sampleDigest
        )
        let alert = ScsPinPrompt.makeAlert(context: context, bundle: bundle)
        #expect(alert.messageText == expected.signature)
        #expect(alert.informativeText.contains(expected.digestPrefix + Self.sampleDigest))
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
    #endif

    @Test
    internal func missingOriginAndMissingSignerFormatCleanlyWithDigest() {
      let bundle = Bundle.main
      let details = ScsConsentDetails.format(
        origin: nil,
        purpose: .authentication,
        signerName: nil,
        sha256Hex: Self.sampleDigest,
        bundle: bundle
      )
      let stated = String(
        localized: "Origin: (none - the request sent no Origin header)", bundle: bundle)
      let action = String(localized: "Action: Log in", bundle: bundle)
      let digest = String(localized: "Digest (SHA-256): \(Self.sampleDigest)", bundle: bundle)
      #expect(details == stated + "\n" + action + "\n" + digest)
    }
  }
#endif
