// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The counter-safe credential probes: retry counters, the status
/// report, and the reference-numbering resolution they share.
///
/// Every probe here is side-effect-free on the card - the VERIFY
/// status form (S1 v4.2 §3.5.1.1) and the GET DATA PIN-container
/// (S1 v4.2 §3.15) both leave every counter untouched - which is what
/// lets resolution ride on the same exchanges the retry floor already
/// pays for. A card that refuses the VERIFY status form before PACE is
/// read through MSE:Set AT instead (CardOperations+PasswordStates.swift),
/// which spends no try either.
extension CardOperations {
  /// Decodes a probe answer into the retry-state vocabulary.
  private static func classify(_ statusWord: StatusWord) -> RetryProbeOutcome {
    switch statusWord {
    case .success:
      .verified

    case .pinIncorrect(let remaining):
      .remaining(remaining)

    case .authenticationFailed:
      .noInformation

    case .authenticationBlocked:
      .locked

    case .referenceDataInvalidated:
      .invalidated

    default:
      .other(statusWord.encoded)
    }
  }

  private static func isRecognizedProbeOutcome(_ outcome: RetryProbeOutcome) -> Bool {
    switch outcome {
    case .invalidated, .locked, .noInformation, .remaining, .verified:
      true

    case .other:
      false
    }
  }

  /// Asks the card which credential reference numbering it uses, once
  /// per session; later calls answer from memory without a command.
  ///
  /// The citizen PIN1 reference is probed first with the counter-safe
  /// VERIFY status form: any recognised PIN state means the citizen
  /// numbering is live. `referenceDataNotFound` is the organization
  /// card's answer - the S4-2 v4.0 §4.2 security-data-object numbering
  /// is then confirmed by probing it the same way. A card answering
  /// neither probe recognisably resolves to citizen, preserving the
  /// behaviour every caller had before this seam existed. Neither
  /// probe touches any retry counter (S1 v4.2 §3.5.1.1).
  public func resolveCredentialReferences() throws -> CredentialReferenceSet {
    if let known = referenceMemo.resolved {
      return known
    }
    let resolved = try probeReferenceNumbering()
    referenceMemo.resolved = resolved
    return resolved
  }

  /// The retry counter outcome already observed for `role` in this session,
  /// or nil before any probe or verification recorded one.
  public func probedRetryCounter(role: CredentialRole) -> RetryProbeOutcome? {
    referenceMemo.probedRetryCounters[role]
  }

  /// Probes one credential's retry counter without side effects: the
  /// VERIFY probe form for PIN1/PIN2, the GET DATA PIN-container form
  /// for the PUK (which has no VERIFY probe on the citizen card).
  ///
  /// Self-resolving: an unresolved session probes the citizen
  /// reference first, and `referenceDataNotFound` re-probes under the
  /// organization numbering - the pair of answers is exactly the
  /// resolution `resolveCredentialReferences()` performs, so the
  /// outcome is remembered for every later command.
  public func probeRetryCounter(role: CredentialRole) throws -> RetryProbeOutcome {
    if let cached = referenceMemo.probedRetryCounters[role] {
      return cached
    }
    let outcome: RetryProbeOutcome
    switch role {
    case .pin1, .pin2:
      outcome = try probePinRetryCounter(role: role)

    case .puk:
      outcome = try probePukRetryCounter()
    }
    referenceMemo.probedRetryCounters[role] = outcome
    return outcome
  }

  /// Probes all three credentials for the explicit status display.
  ///
  /// `includingPuk` exists for diagnostics over an interface that refuses
  /// that one credential. Authentication never calls this method: it
  /// probes PIN1 alone, before VERIFY PIN1.
  public func probeCredentials(includingPuk: Bool = true) throws -> CredentialProbeReport {
    let pin1 = try probeRetryCounter(role: .pin1)
    let pin2 = try probeRetryCounter(role: .pin2)
    let puk = includingPuk ? try probeRetryCounter(role: .puk) : .noInformation
    return CredentialProbeReport(
      pin1: pin1,
      pin2: pin2,
      puk: puk,
      pristineAllowance: pristineRetryAllowance
    )
  }

  /// The VERIFY status probe under the session's numbering.
  ///
  /// Always resolves the numbering through PIN 1 first so a PIN 2 probe on an
  /// unresolved session can never mistake EstEID 2025's `82` PIN 2 reference
  /// for FINEID's identical `82` reference.
  private func probePinRetryCounter(role: CredentialRole) throws -> RetryProbeOutcome {
    let numbering = try resolveCredentialReferences()
    if let cached = referenceMemo.probedRetryCounters[role] {
      return cached
    }
    if numbering == .estonian2018 {
      try selectEstonian2018Root()
      if role == .pin2 {
        try selectChildDirectory(.estonianQscdDirectory)
      }
      let response = try transmit(.readRetryCounter(role: role, references: .estonian2018))
      return Self.classify(response.statusWord)
    }
    let response = try transmit(.readRetryCounter(role: role, references: numbering))
    return sealedReading(of: role, after: response.statusWord)
      ?? Self.classify(response.statusWord)
  }

  /// The PUK counter, from whichever surface this card has.
  ///
  /// FINEID citizen cards and EstEID 2025 expose it through the GET DATA
  /// PIN-container (`83`). EstEID 2018 exposes it through a plain VERIFY
  /// status probe (`02`) under MF. FINEID organization cards expose it
  /// through a plain VERIFY status probe (`12`).
  private func probePukRetryCounter() throws -> RetryProbeOutcome {
    if referenceMemo.resolved == .estonian2018 {
      try selectEstonian2018Root()
      let response = try transmit(.readRetryCounter(role: .puk, references: .estonian2018))
      return Self.classify(response.statusWord)
    }
    if referenceMemo.resolved != .organization {
      let references = referenceMemo.resolved ?? .citizen
      let response = try transmit(
        .readCredentialAttributes(role: .puk, references: references)
      )
      if response.statusWord == .success {
        guard
          let counter = CredentialAttributes.retryCounter(
            fromResponseBody: response.payload
          )
        else {
          return .noInformation
        }
        return .remaining(counter)
      }
      let outcome = Self.classify(response.statusWord)
      guard case .other = outcome, referenceMemo.resolved == nil else {
        return outcome
      }
    }
    let response = try transmit(
      .readRetryCounter(role: .puk, references: .organization)
    )
    return sealedReading(of: .puk, after: response.statusWord)
      ?? Self.classify(response.statusWord)
  }

  /// Resolves the card's PIN numbering by probing PIN 1 across FINEID citizen
  /// (`11`), FINEID organization (`03`), and EstEID 2025 (`81`).
  private func probeReferenceNumbering() throws -> CredentialReferenceSet {
    let citizen = try transmit(.readRetryCounter(role: .pin1, references: .citizen))
    if let sealed = sealedReading(of: .pin1, after: citizen.statusWord) {
      referenceMemo.probedRetryCounters[.pin1] = sealed
      return .organization
    }
    guard citizen.statusWord == .referenceDataNotFound else {
      let outcome = Self.classify(citizen.statusWord)
      referenceMemo.probedRetryCounters[.pin1] = outcome
      return .citizen
    }
    let organization = try transmit(
      .readRetryCounter(role: .pin1, references: .organization)
    )
    let organizationOutcome = Self.classify(organization.statusWord)
    if Self.isRecognizedProbeOutcome(organizationOutcome) {
      referenceMemo.probedRetryCounters[.pin1] = organizationOutcome
      return .organization
    }
    let estonian2025 = try transmit(
      .readRetryCounter(role: .pin1, references: .estonian2025)
    )
    let estonianOutcome = Self.classify(estonian2025.statusWord)
    if Self.isRecognizedProbeOutcome(estonianOutcome) {
      referenceMemo.probedRetryCounters[.pin1] = estonianOutcome
      return .estonian2025
    }
    referenceMemo.probedRetryCounters[.pin1] = organizationOutcome
    return .citizen
  }
}
