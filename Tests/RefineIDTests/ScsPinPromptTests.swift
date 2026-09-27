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
  }

  @Test(arguments: ["en", "fi", "sv"])
  internal func localizedPrompt(language: String) async throws {
    let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
    let bundle = try #require(Bundle(path: path))
    let alert = ScsPinPrompt.makeAlert(role: .pin2, bundle: bundle)
    let expected: ExpectedLabels
    switch language {
    case "fi":
      expected = ExpectedLabels(
        basic: "Sy\u{00F6}t\u{00E4} Perus (PIN 1)",
        signature: "Sy\u{00F6}t\u{00E4} Allekirjoitus (PIN 2)",
        sign: "Allekirjoita", cancel: "Peruuta")
    case "sv":
      expected = ExpectedLabels(
        basic: "Ange Bas (PIN 1)", signature: "Ange Signaturkoden (PIN 2)",
        sign: "Signera", cancel: "Avbryt")
    default:
      expected = ExpectedLabels(
        basic: "Enter Basic (PIN 1)", signature: "Enter Signature (PIN 2)",
        sign: "Sign", cancel: "Cancel")
    }
    #expect(alert.messageText == expected.signature)
    let basic = ScsPinPrompt.makeAlert(role: .pin1, bundle: bundle)
    #expect(basic.messageText == expected.basic)
    #expect(alert.informativeText.isEmpty)
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
}
