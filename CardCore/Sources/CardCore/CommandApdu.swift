// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A read-only, idempotent command APDU.
///
/// Every command constructible here is safe to retransmit: it carries no
/// credential and has no side effect on retry counters. Credential-
/// bearing commands are a different, noncopyable type
/// (`CredentialBearingCommand`), so the safety class of every command is
/// part of its type (Documentation/release-plan.md section 5).
public struct CommandApdu: Equatable, Sendable {
  /// A short case-4 command split for CryptoTokenKit's structured API.
  ///
  /// CTK can keep a T=0 continuation inside one operation when given the
  /// command this way. That is required for protected modulus-wide RSA
  /// PSO:CDS responses: RSA-3072 cannot fit one short response, and the
  /// secure-messaging envelope takes a 256-byte RSA-2048 result over it.
  public struct StructuredCase4: Equatable, Sendable {
    /// Command class byte.
    public let cla: UInt8

    /// Instruction byte.
    public let ins: UInt8

    /// First instruction parameter.
    public let parameter1: UInt8

    /// Second instruction parameter.
    public let parameter2: UInt8

    /// Command data, excluding its length byte.
    public let data: Data

    /// Expected response length passed to CryptoTokenKit.
    public let expectedLength: Int
  }

  /// The wire bytes handed to the transport.
  public let encoded: Data

  /// SELECT by application identifier, first occurrence, no FCI
  /// requested: `00 A4 04 0C Lc AID` (FINEID S1 v4.2; ISO 7816-4
  /// §11.1.1).
  public static func selectApplication(_ aid: ApplicationIdentifier) -> Self {
    var bytes: [UInt8] = [
      Iso7816Values.classInterindustry,
      Iso7816Values.insSelect,
      Iso7816Values.selectByAidP1,
      Iso7816Values.selectByAidNoFciP2,
    ]
    bytes.append(UInt8(aid.bytes.count))
    bytes.append(contentsOf: aid.bytes)
    return Self(encoded: Data(bytes))
  }

  /// SELECT an elementary file under the current DF (S1 v4.2 §3.2.2).
  ///
  /// Wire shape `00 A4 02 0C 02 FID`, no response data requested.
  /// Selecting the eID application first makes its DF current; this
  /// then selects EFs beneath it without any FCI parsing.
  public static func selectElementaryFile(_ file: FileIdentifier) -> Self {
    var bytes: [UInt8] = [
      Iso7816Values.classInterindustry,
      Iso7816Values.insSelect,
      Iso7816Values.selectEfUnderCurrentDfP1,
      Iso7816Values.selectNoResponseP2,
    ]
    bytes.append(UInt8(file.bytes.count))
    bytes.append(contentsOf: file.bytes)
    return Self(encoded: Data(bytes))
  }

  /// SELECT a file by identifier with an explicit P1, no response data:
  /// `00 A4 <p1> 0C 02 FID` (ISO 7816-4 §11.1.1).
  ///
  /// Card generations accept different P1 encodings for the main file
  /// and child directories; `CardOperations` tries the proven variants
  /// in order (ported from the reference implementation), so the P1 is
  /// a named value chosen by the caller, never a bare literal.
  public static func selectFile(
    _ file: FileIdentifier,
    selectionP1: UInt8
  ) -> Self {
    var bytes: [UInt8] = [
      Iso7816Values.classInterindustry,
      Iso7816Values.insSelect,
      selectionP1,
      Iso7816Values.selectNoResponseP2,
    ]
    bytes.append(UInt8(file.bytes.count))
    bytes.append(contentsOf: file.bytes)
    return Self(encoded: Data(bytes))
  }

  /// READ BINARY from the current EF: `00 B0 P1 P2 Le`
  /// (ISO 7816-4 §11.2.2).
  public static func readBinary(
    offset: ReadOffset,
    expectedLength: ExpectedResponseLength
  ) -> Self {
    Self(
      encoded: Data([
        Iso7816Values.classInterindustry,
        Iso7816Values.insReadBinary,
        offset.p1Byte,
        offset.p2Byte,
        expectedLength.encodedByte,
      ])
    )
  }

  /// The side-effect-free retry-counter probe (FINEID S1 v4.2 §3.5.1.1;
  /// GED24035 §7.5.1.1; ID1 Developer Guide 2025 §9.3.1).
  ///
  /// VERIFY with no credential data: the card answers `63Cx` with the
  /// remaining attempts in the counter nibble and no attempt is
  /// consumed. EstEID 2018 IAS-ECC takes the 4-byte Case 1 form
  /// (`00 20 00 <ref>`); Thales and FINEID cards take `Lc=00`.
  public static func readRetryCounter(
    role: CredentialRole,
    references: CredentialReferenceSet
  ) -> Self {
    if references == .estonian2018 {
      return Self(
        encoded: Data([
          Iso7816Values.classInterindustry,
          Iso7816Values.insVerify,
          Iso7816Values.verifyModeP1,
          references.reference(for: role),
        ])
      )
    }
    return Self(
      encoded: Data([
        Iso7816Values.classInterindustry,
        Iso7816Values.insVerify,
        Iso7816Values.verifyModeP1,
        references.reference(for: role),
        0,
      ])
    )
  }

  /// GET RESPONSE for a T=0 `61xx` continuation (ISO 7816-4 §11.7.1).
  ///
  /// `00 C0 00 00 Le` where Le is the announced count; a count of zero
  /// announces 256 or more and requests the short-form maximum.
  public static func getResponse(announcedCount: UInt8) -> Self {
    let expected =
      announcedCount == 0
      ? Iso7816Values.expectedLengthMaximumEncoding
      : announcedCount
    return Self(
      encoded: Data([
        Iso7816Values.classInterindustry,
        Iso7816Values.insGetResponse,
        0,
        0,
        expected,
      ])
    )
  }

  /// MANAGE SECURITY ENVIRONMENT: SET the Digital Signature Template to
  /// a signing key and algorithm (FINEID S1 v4.2 §3.6).
  ///
  /// The data field is two control-reference data objects: the
  /// algorithm reference, then the key reference. Pins the card to sign
  /// with the named key under the given algorithm; PSO:CDS then
  /// produces the signature. Not credential-bearing - the key's gating
  /// PIN is verified separately.
  public static func selectSigningEnvironment(
    algorithm: SigningAlgorithm,
    key: CardSigningKey
  ) -> Self {
    selectSigningEnvironment(algorithm: algorithm, keyReference: key.reference)
  }

  /// `selectSigningEnvironment(algorithm:key:)` with an explicit key
  /// reference byte, for a numbering where the byte is not the key's
  /// own: a key local to the current DF carries bit 8 over its number
  /// (IAS-ECC v1.0.1 §4.4), which is how the organization card's
  /// qualified key is named inside DF.ESIGN.
  public static func selectSigningEnvironment(
    algorithm: SigningAlgorithm,
    keyReference: UInt8
  ) -> Self {
    let crdo: [UInt8] = [
      FineidValues.crdoAlgorithmReferenceTag,
      FineidValues.crdoValueLength,
      algorithm.reference,
      FineidValues.crdoKeyReferenceTag,
      FineidValues.crdoValueLength,
      keyReference,
    ]
    var bytes: [UInt8] = [
      Iso7816Values.classInterindustry,
      Iso7816Values.insManageSecurityEnvironment,
      Iso7816Values.mseSetP1,
      Iso7816Values.mseDigitalSignatureTemplateP2,
      UInt8(crdo.count),
    ]
    bytes.append(contentsOf: crdo)
    return Self(encoded: Data(bytes))
  }

  /// PERFORM SECURITY OPERATION: COMPUTE DIGITAL SIGNATURE over a
  /// host-supplied digest (FINEID S1 v4.2 §3.8).
  ///
  /// Wire shape `00 2A 9E 9A <Lc> <digest> 00`: the card signs the
  /// digest under the environment selected by
  /// `selectSigningEnvironment` and returns the signature. Digests are
  /// short (<= 64 bytes), so the short form always applies. The card may
  /// answer `6Cxx` (wrong Le) for an ECDSA signature; `CardOperations`
  /// re-issues with the exact length.
  public static func computeSignature(overDigest digest: Data) -> Self {
    var bytes: [UInt8] = [
      Iso7816Values.classInterindustry,
      Iso7816Values.insPerformSecurityOperation,
      Iso7816Values.psoComputeSignatureP1,
      Iso7816Values.psoComputeSignatureP2,
      UInt8(digest.count),
    ]
    bytes.append(contentsOf: digest)
    bytes.append(Iso7816Values.expectedLengthMaximumEncoding)
    return Self(encoded: Data(bytes))
  }

  /// PSO:CDS re-issued with an exact Le, answering a `6Cxx` correction.
  public static func computeSignature(
    overDigest digest: Data,
    exactLength: ExpectedResponseLength
  ) -> Self {
    var bytes: [UInt8] = [
      Iso7816Values.classInterindustry,
      Iso7816Values.insPerformSecurityOperation,
      Iso7816Values.psoComputeSignatureP1,
      Iso7816Values.psoComputeSignatureP2,
      UInt8(digest.count),
    ]
    bytes.append(contentsOf: digest)
    bytes.append(exactLength.encodedByte)
    return Self(encoded: Data(bytes))
  }

  /// PSO:HASH loading a host-computed digest as the external hash for
  /// the next PSO:CDS (FINEID S1 v4.2 §3.7).
  ///
  /// Wire shape `00 2A 90 A0 <Lc> 90 <len> <digest>`. FINEID auth-key
  /// signing (ECDSA, and pre-hashed RSA) loads the digest here and then
  /// produces the signature with an *empty* PSO:CDS; the digest is never
  /// carried inline in PSO:CDS (that shape draws `6985`). Not
  /// credential-bearing - the PIN is verified separately.
  public static func loadExternalHash(_ digest: Data) -> Self {
    var hashObject: [UInt8] = [
      Iso7816Values.psoHashValueTag,
      UInt8(digest.count),
    ]
    hashObject.append(contentsOf: digest)
    var bytes: [UInt8] = [
      Iso7816Values.classInterindustry,
      Iso7816Values.insPerformSecurityOperation,
      Iso7816Values.psoHashP1,
      Iso7816Values.psoHashExternalP2,
      UInt8(hashObject.count),
    ]
    bytes.append(contentsOf: hashObject)
    return Self(encoded: Data(bytes))
  }

  /// PSO:CDS with an empty body, signing the hash previously loaded by
  /// `loadExternalHash` (FINEID S1 v4.2 §3.8).
  ///
  /// Wire shape `00 2A 9E 9A 00`: MSE:SET and PSO:HASH have set the
  /// environment and the digest, so the card just returns the signature.
  /// `Le=00` requests the short-form maximum; an ECDSA card answers
  /// `6Cxx` with the exact length and `CardOperations` re-issues.
  public static func computeSignatureOverLoadedHash() -> Self {
    Self(
      encoded: Data([
        Iso7816Values.classInterindustry,
        Iso7816Values.insPerformSecurityOperation,
        Iso7816Values.psoComputeSignatureP1,
        Iso7816Values.psoComputeSignatureP2,
        Iso7816Values.expectedLengthMaximumEncoding,
      ])
    )
  }

  /// Empty-body PSO:CDS re-issued with an exact Le, answering a `6Cxx`
  /// correction from the loaded-hash signature.
  public static func computeSignatureOverLoadedHash(
    exactLength: ExpectedResponseLength
  ) -> Self {
    Self(
      encoded: Data([
        Iso7816Values.classInterindustry,
        Iso7816Values.insPerformSecurityOperation,
        Iso7816Values.psoComputeSignatureP1,
        Iso7816Values.psoComputeSignatureP2,
        exactLength.encodedByte,
      ])
    )
  }

  /// Splits only a protected maximum-length PSO:CDS for CTK's structured
  /// send API.
  ///
  /// The maximum-length form is the RSA path that needs CTK to keep T=0
  /// continuation inside one callback. Exact-length ECDSA and every other
  /// APDU remain byte-exact on the raw transmit path.
  public static func structuredProtectedSignature(
    _ command: Data
  ) -> StructuredCase4? {
    let classIndex = 0
    let instructionIndex = 1
    let parameter1Index = 2
    let parameter2Index = 3
    let dataLengthIndex = 4
    let headerLength = 5
    let expectedLengthBytes = 1
    let protectedClass =
      Iso7816Values.classInterindustry | PaceValues.classSecureMessagingBit
    let bytes = Array(command)
    guard
      bytes.count >= headerLength + expectedLengthBytes,
      bytes[classIndex] == protectedClass,
      bytes[instructionIndex] == Iso7816Values.insPerformSecurityOperation,
      bytes[parameter1Index] == Iso7816Values.psoComputeSignatureP1,
      bytes[parameter2Index] == Iso7816Values.psoComputeSignatureP2
    else {
      return nil
    }
    let dataLength = Int(bytes[dataLengthIndex])
    guard bytes.count == headerLength + dataLength + expectedLengthBytes else {
      return nil
    }
    let dataStart = headerLength
    let dataEnd = dataStart + dataLength
    let encodedLength = bytes[dataEnd]
    guard encodedLength == Iso7816Values.expectedLengthMaximumEncoding else {
      return nil
    }
    return StructuredCase4(
      cla: protectedClass,
      ins: Iso7816Values.insPerformSecurityOperation,
      parameter1: Iso7816Values.psoComputeSignatureP1,
      parameter2: Iso7816Values.psoComputeSignatureP2,
      data: Data(bytes[dataStart..<dataEnd]),
      expectedLength: 0)
  }
}
