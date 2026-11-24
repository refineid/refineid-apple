// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The signing operations: the MSE / PSO chain for both card keys.
///
/// One shared core drives the chain; the public entry points differ
/// only in the key they name and the PIN their contracts demand. The
/// chain's shape follows the reference numbering the session resolved
/// when its PIN was verified: the citizen card loads the digest with
/// PSO:HASH and signs with an empty PSO:CDS, while the organization
/// card has no external-hash PSO:HASH - the digest rides inline in
/// PSO:CDS (Idemia organizational cards specification §6.6.2.3).
extension CardOperations {
  /// Normalizes a digest to EstEID 2018's 48-byte P-384 input width.
  ///
  /// Left-pads shorter digests (such as SHA-256) with zeros, and takes the
  /// leftmost 48 bytes of longer digests (such as SHA-512) per ID1 Developer
  /// Guide 2025 section 9.5.1.
  internal static func estonian2018Digest(_ digest: Data) -> Data {
    let targetLength = EstonianEidValues.p384DigestLength
    if digest.count == targetLength {
      return digest
    }
    if digest.count < targetLength {
      return Data(repeating: 0, count: targetLength - digest.count) + digest
    }
    return Data(digest.prefix(targetLength))
  }

  /// Computes an authentication signature over `digest` with the
  /// PIN1-gated key.
  ///
  /// PIN1 must already be verified in this session.
  public func computeAuthenticationSignature(
    overDigest digest: Data,
    algorithm: SigningAlgorithm,
    expectedSignatureLength: ExpectedResponseLength?
  ) throws -> Data {
    try computeSignature(
      overDigest: digest,
      algorithm: algorithm,
      key: .authentication,
      expectedSignatureLength: expectedSignatureLength
    )
  }

  /// Computes a qualified signature over `digest` with the PIN2-gated
  /// key.
  ///
  /// PIN2 must have been verified in this session, immediately before
  /// this call - it is never cached, so one verification serves one
  /// signature.
  public func computeQualifiedSignature(
    overDigest digest: Data,
    algorithm: SigningAlgorithm,
    expectedSignatureLength: ExpectedResponseLength?
  ) throws -> Data {
    try computeSignature(
      overDigest: digest,
      algorithm: algorithm,
      key: .qualifiedSignature,
      expectedSignatureLength: expectedSignatureLength
    )
  }

  /// Drives the FINEID sign chain (S1 v4.2 §3.6-3.8).
  ///
  /// MSE:SET DST pins the key and algorithm; PSO:HASH loads the host
  /// digest as the external hash; an empty PSO:CDS then returns the
  /// signature. The digest is loaded via PSO:HASH, never carried inline
  /// in PSO:CDS - the citizen card rejects the inline shape, exactly as
  /// the organization card rejects this one, which is why the resolved
  /// numbering picks the chain. Both keys are PIN-gated, so every
  /// caller verified a PIN in this session first and that verification
  /// resolved the numbering; a session that never did resolves as
  /// citizen and keeps the historical chain.
  ///
  /// P-384 and RSA-2048 carry their exact short-response length as `Le`
  /// up front. The G4E card is T=0-only and a `6Cxx` between PSO:HASH and
  /// a re-issued PSO:CDS can drop the loaded hash, making the card sign
  /// silently-meaningless bytes (S1 v4.2 §3.8.1.1), so this path never
  /// retries that operation. RSA-3072 cannot fit an exact short `Le`; it
  /// uses `00` and the transport keeps its continuation within the
  /// operation. The key's gating PIN must already be verified in this
  /// session. Returns the raw card signature: `r || s` for ECDSA, or one
  /// modulus-wide block for RSA.
  private func computeSignature(
    overDigest digest: Data,
    algorithm: SigningAlgorithm,
    key: CardSigningKey,
    expectedSignatureLength: ExpectedResponseLength?
  ) throws -> Data {
    if referenceMemo.resolved == .estonian2018 {
      return try computeEstonian2018Signature(overDigest: digest, key: key)
    }
    let selected = try transmit(
      .selectSigningEnvironment(
        algorithm: algorithm, keyReference: keyReference(for: key))
    )
    guard selected.statusWord == .success else {
      throw CardOperationError.signRejected(selected.statusWord)
    }
    if referenceMemo.resolved != .organization {
      let hashed = try transmit(.loadExternalHash(digest))
      guard hashed.statusWord == .success else {
        throw CardOperationError.signRejected(hashed.statusWord)
      }
    }
    let signed = try transmitSignature(
      signatureCommand(
        overDigest: digest,
        expectedSignatureLength: expectedSignatureLength
      )
    )
    guard signed.statusWord == .success else {
      throw CardOperationError.signRejected(signed.statusWord)
    }
    return signed.payload
  }

  /// EstEID 2018 signing over a 48-byte P-384 digest (ID1 Developer Guide 2025
  /// sections 9.5.1 and 9.6).
  ///
  /// Authentication selects `MF -> ADF1` (preserving global PIN 1 verification),
  /// runs `MSE:SET AT`, and signs with `INTERNAL AUTHENTICATE`. Qualified
  /// signing runs inside the already-selected `ADF2` (where local PIN 2 was
  /// just verified), runs `MSE:SET DST`, and signs with `PSO:CDS`.
  private func computeEstonian2018Signature(
    overDigest digest: Data,
    key: CardSigningKey
  ) throws -> Data {
    let normalized = Self.estonian2018Digest(digest)
    switch key {
    case .authentication:
      try selectEstonian2018Root()
      try selectChildDirectory(.estonianAwpDirectory)
      let selected = try transmit(.selectEstonian2018AuthenticationEnvironment())
      guard selected.statusWord == .success else {
        throw CardOperationError.signRejected(selected.statusWord)
      }
      let signed = try transmitSignature(.internalAuthenticate(overDigest: normalized))
      guard signed.statusWord == .success else {
        throw CardOperationError.signRejected(signed.statusWord)
      }
      return signed.payload

    case .qualifiedSignature:
      let selected = try transmit(.selectEstonian2018SigningEnvironment())
      guard selected.statusWord == .success else {
        throw CardOperationError.signRejected(selected.statusWord)
      }
      let signed = try transmitSignature(.computeSignature(overDigest: normalized))
      guard signed.statusWord == .success else {
        throw CardOperationError.signRejected(signed.statusWord)
      }
      return signed.payload
    }
  }

  /// The key reference the session's numbering names `key` by.
  ///
  /// - FINEID organization qualified key: local key `82` in `DF.ESIGN`.
  /// - EstEID 2025: live `EF.PrKD` key reference (defaults `01` / `05`).
  /// - FINEID citizen: `01` / `02`.
  private func keyReference(for key: CardSigningKey) -> UInt8 {
    switch referenceMemo.resolved {
    case .organization where key == .qualifiedSignature:
      return FineidValues.organizationQualifiedKeyReference

    case .estonian2025:
      if let discovered = referenceMemo.discoveredKeyReferences[key] {
        return discovered
      }
      return key == .authentication
        ? EstonianEidValues.defaultAuthKeyReference2025
        : EstonianEidValues.defaultQualifiedKeyReference2025

    default:
      return key.reference
    }
  }

  /// The one PSO:CDS this session's chain ends with: empty-bodied over
  /// the loaded hash on the citizen card and EstEID 2025, the digest inline on
  /// the organization card, with the exact `Le` whenever the response fits
  /// a short APDU.
  private func signatureCommand(
    overDigest digest: Data,
    expectedSignatureLength: ExpectedResponseLength?
  ) -> CommandApdu {
    guard referenceMemo.resolved != .organization else {
      return expectedSignatureLength.map { exact in
        CommandApdu.computeSignature(overDigest: digest, exactLength: exact)
      } ?? .computeSignature(overDigest: digest)
    }
    return expectedSignatureLength.map(
      CommandApdu.computeSignatureOverLoadedHash(exactLength:)
    ) ?? .computeSignatureOverLoadedHash()
  }

  /// Diagnostic sibling of `computeAuthenticationSignature` that records
  /// each command's status word instead of throwing at the first
  /// non-`9000`, so a probe can isolate which step a card rejects.
  public func computeAuthenticationSignatureTraced(
    overDigest digest: Data,
    algorithm: SigningAlgorithm,
    expectedSignatureLength: ExpectedResponseLength?
  ) throws -> (raw: Data?, steps: [(command: String, statusWord: UInt16)]) {
    var steps: [(command: String, statusWord: UInt16)] = []
    if referenceMemo.resolved == .estonian2018 {
      try selectEstonian2018Root()
      try selectChildDirectory(.estonianAwpDirectory)
      let selected = try transmit(.selectEstonian2018AuthenticationEnvironment())
      steps.append((command: "MSE:SET AT", statusWord: selected.statusWord.encoded))
      guard selected.statusWord == .success else { return (nil, steps) }
      let signed = try transmitSignature(
        .internalAuthenticate(overDigest: Self.estonian2018Digest(digest))
      )
      steps.append((command: "INTERNAL AUTHENTICATE", statusWord: signed.statusWord.encoded))
      guard signed.statusWord == .success else { return (nil, steps) }
      return (signed.payload, steps)
    }
    let selected = try transmit(
      .selectSigningEnvironment(
        algorithm: algorithm,
        keyReference: keyReference(for: .authentication)
      )
    )
    steps.append((command: "MSE:SET", statusWord: selected.statusWord.encoded))
    guard selected.statusWord == .success else { return (nil, steps) }
    if referenceMemo.resolved != .organization {
      let hashed = try transmit(.loadExternalHash(digest))
      steps.append((command: "PSO:HASH", statusWord: hashed.statusWord.encoded))
      guard hashed.statusWord == .success else { return (nil, steps) }
    }
    let signed = try transmitSignature(
      signatureCommand(
        overDigest: digest,
        expectedSignatureLength: expectedSignatureLength
      )
    )
    steps.append((command: "PSO:CDS", statusWord: signed.statusWord.encoded))
    guard signed.statusWord == .success else { return (nil, steps) }
    return (signed.payload, steps)
  }

  /// Transmits PSO:CDS without applying the short-response parser cap.
  ///
  /// RSA-2048 returns the short maximum of 256 bytes, while RSA-3072
  /// returns 384. A structured CTK send may deliver a continued result
  /// in one callback, while a raw reader path may still expose `61xx`;
  /// ``ContinuedResponse`` handles both forms.
  private func transmitSignature(_ command: CommandApdu) throws -> ResponseApdu {
    let response = try ContinuedResponse.transmitting(command.encoded, over: channel)
    return ResponseApdu(payload: response.payload, statusWord: response.statusWord)
  }
}
