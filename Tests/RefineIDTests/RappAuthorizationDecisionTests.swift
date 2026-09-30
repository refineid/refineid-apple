// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

@testable import RefineID

@Suite("RAPP authorization decision and PIN custody")
internal struct RappAuthorizationDecisionTests {
  @Test("Types reachable from authorization decision do not conform to string conversion protocols")
  internal func nonConvertibleCredentialTypes() {
    #expect(!(RappAuthorizationDecision.self is CustomStringConvertible.Type))
    #expect(!(Pin1AuthorizationDigits.self is CustomStringConvertible.Type))
    #expect(!(Pin2AuthorizationDigits.self is CustomStringConvertible.Type))

    #expect(!(RappAuthorizationDecision.self is CustomDebugStringConvertible.Type))
    #expect(!(Pin1AuthorizationDigits.self is CustomDebugStringConvertible.Type))
    #expect(!(Pin2AuthorizationDigits.self is CustomDebugStringConvertible.Type))
  }

  @Test("String interpolation and reflection of authorization decision omit credentials")
  internal func stringInterpolationDoesNotDiscloseDigits() throws {
    let pin1Digits = try #require(Pin1AuthorizationDigits(digits: "1234"))
    let decision1 = RappAuthorizationDecision.approvedBrowserAuthentication(pin1: pin1Digits)

    let pin2Digits = try #require(Pin2AuthorizationDigits(digits: "123456"))
    let decision2 = RappAuthorizationDecision.approvedDocumentSignature(pin2: pin2Digits)

    #expect(!String(describing: decision1).contains("1234"))
    #expect(!String(describing: pin1Digits).contains("1234"))
    #expect(!String(describing: decision2).contains("123456"))
    #expect(!String(describing: pin2Digits).contains("123456"))

    #expect(!String(format: "%@", String(describing: decision1)).contains("1234"))
    #expect(!String(format: "%@", String(describing: decision2)).contains("123456"))

    #expect(decision1.summary == "approvedBrowserAuthentication")
    #expect(decision2.summary == "approvedDocumentSignature")
    #expect(RappAuthorizationDecision.approved.summary == "approved")
    #expect(RappAuthorizationDecision.denied.summary == "denied")

    let mirror1 = Mirror(reflecting: pin1Digits)
    #expect(mirror1.children.isEmpty)

    let mirror2 = Mirror(reflecting: pin2Digits)
    #expect(mirror2.children.isEmpty)
  }

  @Test("Authorization digit wrappers validate against PIN rules")
  internal func digitValidationBounds() {
    #expect(Pin1AuthorizationDigits(digits: "") == nil)
    #expect(Pin1AuthorizationDigits(digits: "123") == nil)
    #expect(Pin1AuthorizationDigits(digits: "1234567890123") == nil)
    #expect(Pin1AuthorizationDigits(digits: "123a") == nil)
    #expect(Pin1AuthorizationDigits(digits: "1234") != nil)

    #expect(Pin2AuthorizationDigits(digits: "") == nil)
    #expect(Pin2AuthorizationDigits(digits: "1234") == nil)
    #expect(Pin2AuthorizationDigits(digits: "12345") == nil)
    #expect(Pin2AuthorizationDigits(digits: "1234567890123") == nil)
    #expect(Pin2AuthorizationDigits(digits: "12345a") == nil)
    #expect(Pin2AuthorizationDigits(digits: "123456") != nil)
  }
}
