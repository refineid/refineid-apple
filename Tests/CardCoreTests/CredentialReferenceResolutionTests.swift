// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

/// The reference-numbering resolver over a scripted channel: the
/// counter-safe VERIFY status probe (S1 v4.2 §3.5.1.1) against the
/// citizen numbering first, then the S4-2 v4.0 §4.2 numbering when the
/// citizen reference is absent.
@Suite
internal struct CredentialReferenceResolutionTests {
  @Test
  internal func citizenAnswerShortCircuitsTheResolution() throws {
    let channel = ScriptedChannel([
      ("0020001100", "63C5")
    ])
    let operations = CardOperations(channel: channel)
    #expect(try operations.resolveCredentialReferences() == .citizen)
    // The second call answers from session memory, sending nothing.
    #expect(try operations.resolveCredentialReferences() == .citizen)
    #expect(channel.isExhausted)
  }

  @Test
  internal func absentCitizenReferenceResolvesOrganization() throws {
    // 6A88 (referenced data not found) is the organization card's
    // answer to the citizen PIN1 reference; the PIN AUTH object then
    // confirms the S4-2 numbering with a retry count.
    let channel = ScriptedChannel([
      ("0020001100", "6A88"),
      ("0020000300", "63C5"),
    ])
    let operations = CardOperations(channel: channel)
    #expect(try operations.resolveCredentialReferences() == .organization)
    #expect(channel.isExhausted)
  }

  @Test
  internal func unrecognisedAnswersFallBackToCitizen() throws {
    // A card answering neither probe recognisably resolves to citizen,
    // preserving the behaviour every caller had before this seam.
    let channel = ScriptedChannel([
      ("0020001100", "6A88"),
      ("0020000300", "6A86"),
      ("0020008100", "6A88"),
    ])
    let operations = CardOperations(channel: channel)
    #expect(try operations.resolveCredentialReferences() == .citizen)
    #expect(channel.isExhausted)
  }

  @Test
  internal func retryProbesResolveAndReuseTheNumbering() throws {
    let five = try #require(RetryCount(attemptsRemaining: 5))
    // The PIN1 probe pair resolves the numbering; PIN2 and the PUK
    // then probe their organization objects directly (S4-2 v4.0
    // §4.2-4.3), the PUK through its own VERIFY status probe because
    // the citizen PIN-container does not exist there.
    let channel = ScriptedChannel([
      ("0020001100", "6A88"),
      ("0020000300", "63C5"),
      ("0020000400", "63C5"),
      ("0020001200", "63C5"),
    ])
    let report = try CardOperations(channel: channel).probeCredentials()
    #expect(report.pin1 == .remaining(five))
    #expect(report.pin2 == .remaining(five))
    #expect(report.puk == .remaining(five))
    #expect(channel.isExhausted)
  }

  @Test
  internal func pukProbeFallsBackToTheOrganizationObject() throws {
    let five = try #require(RetryCount(attemptsRemaining: 5))
    // An unresolved session still tries the citizen PIN-container
    // first; a refusal outside the modelled credential states falls
    // back to the PIN PUK object's VERIFY status probe (S4-2 v4.0
    // §4.3.2).
    let channel = ScriptedChannel([
      ("00CB00FF05A00383018300", "6A86"),
      ("0020001200", "63C5"),
    ])
    let outcome = try CardOperations(channel: channel)
      .probeRetryCounter(role: .puk)
    #expect(outcome == .remaining(five))
    #expect(channel.isExhausted)
  }
}
