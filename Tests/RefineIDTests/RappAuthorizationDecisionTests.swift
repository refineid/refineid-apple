// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

@testable import RefineIDTestHost

@Suite("RAPP authorization decision and PIN custody")
internal struct RappAuthorizationDecisionTests {
  private static let pin1Digits = "1234"
  private static let pin2Digits = "123456"

  @Test("Types reachable from authorization decision do not conform to string conversion protocols")
  internal func nonConvertibleCredentialTypes() {
    #expect(!(RappAuthorizationDecision.self is CustomStringConvertible.Type))
    #expect(!(Pin1Entry.self is CustomStringConvertible.Type))
    #expect(!(Pin2Entry.self is CustomStringConvertible.Type))

    #expect(!(RappAuthorizationDecision.self is CustomDebugStringConvertible.Type))
    #expect(!(Pin1Entry.self is CustomDebugStringConvertible.Type))
    #expect(!(Pin2Entry.self is CustomDebugStringConvertible.Type))
  }

  @Test("String interpolation and reflection of authorization decision omit credentials")
  internal func stringInterpolationDoesNotDiscloseDigits() throws {
    let pin1 = try #require(Pin1Entry(digits: Self.pin1Digits))
    let decision1 = RappAuthorizationDecision.approvedBrowserAuthentication(pin1: pin1)

    let pin2 = try #require(Pin2Entry(digits: Self.pin2Digits))
    let decision2 = RappAuthorizationDecision.approvedDocumentSignature(pin2: pin2)

    #expect(!String(describing: decision1).contains(Self.pin1Digits))
    #expect(!String(describing: pin1).contains(Self.pin1Digits))
    #expect(!String(describing: decision2).contains(Self.pin2Digits))
    #expect(!String(describing: pin2).contains(Self.pin2Digits))

    #expect(!String(format: "%@", String(describing: decision1)).contains(Self.pin1Digits))
    #expect(!String(format: "%@", String(describing: decision2)).contains(Self.pin2Digits))

    #expect(decision1.summary == "approvedBrowserAuthentication")
    #expect(decision2.summary == "approvedDocumentSignature")
    #expect(RappAuthorizationDecision.denied.summary == "denied")

    #expect(Mirror(reflecting: pin1).children.isEmpty)
    #expect(Mirror(reflecting: pin2).children.isEmpty)
  }
}
