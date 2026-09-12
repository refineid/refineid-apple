// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Security

@testable import RefineID

/// The X.509 certificate factory for the generated signers.
extension SignerCertificateFixtures {

  /// Empty BasicConstraints denotes an explicit end entity.
  private static var endEntityExtension: Data {
    Self.certificateExtension(
      identifier: Self.basicConstraintsOid,
      value: DerEncoder.sequence([])
    )
  }

  /// BasicConstraints with CA=true.
  private static var certificateAuthorityExtension: Data {
    Self.certificateExtension(
      identifier: Self.basicConstraintsOid,
      value: DerEncoder.sequence([
        DerEncoder.tlv(Self.booleanTag, Data([Self.booleanTrue]))
      ])
    )
  }

  /// Estonia's current integer-only BasicConstraints path length.
  private static var endEntityPathLengthExtension: Data {
    Self.certificateExtension(
      identifier: Self.basicConstraintsOid,
      value: DerEncoder.sequence([DerEncoder.integer(0)])
    )
  }

  /// KeyUsage containing digitalSignature.
  private static var signingKeyUsageExtension: Data {
    Self.keyUsageExtension(firstByte: UInt8(1) << (UInt8.bitWidth - 1))
  }

  /// KeyUsage containing only keyEncipherment.
  private static var encryptionKeyUsageExtension: Data {
    Self.keyUsageExtension(
      firstByte: UInt8(1) << (UInt8.bitWidth - Self.keyEnciphermentBitOffset)
    )
  }

  /// Generates a signer with the standard end-entity certificate profile.
  internal static func makeSigner(for profile: Profile) throws -> Signer {
    try Self.makeSigner(for: profile, certificateProfile: .valid)
  }

  /// Generates a private key and self-signed certificate for a profile.
  internal static func makeSigner(
    for profile: Profile,
    certificateProfile: CertificateProfile
  ) throws -> Signer {
    try Self.makeSigner(
      for: profile,
      certificateProfile: certificateProfile,
      subjectPublicKeyProfile: .rsaEncryption
    )
  }

  /// Generates a signer with a controlled SubjectPublicKeyInfo encoding.
  internal static func makeSigner(
    for profile: Profile,
    certificateProfile: CertificateProfile,
    subjectPublicKeyProfile: SubjectPublicKeyProfile
  ) throws -> Signer {
    let key = try Self.makeKey(profile.keyKind)
    let certificate = try Self.certificate(
      for: profile.keyKind,
      key: key,
      profile: certificateProfile,
      subjectPublicKeyProfile: subjectPublicKeyProfile
    )
    guard SecCertificateCreateWithData(nil, certificate as CFData) != nil else {
      throw Failure.keyCreation
    }
    return Signer(certificate: certificate, key: key)
  }

  /// Generates a test certificate with one exact encoded issuer Name.
  internal static func makeSigner(
    for profile: Profile,
    issuerName: Data
  ) throws -> Signer {
    let key = try Self.makeKey(profile.keyKind)
    let certificate = try Self.certificate(
      for: profile.keyKind,
      key: key,
      profile: .valid,
      subjectPublicKeyProfile: .rsaEncryption,
      issuerName: issuerName
    )
    return Signer(certificate: certificate, key: key)
  }

  /// Builds raw certificate bytes for negative SPKI parser tests.
  internal static func makeUncheckedSigner(
    for profile: Profile,
    subjectPublicKeyProfile: SubjectPublicKeyProfile
  ) throws -> Signer {
    let key = try Self.makeKey(profile.keyKind)
    let certificate = try Self.certificate(
      for: profile.keyKind,
      key: key,
      profile: .valid,
      subjectPublicKeyProfile: subjectPublicKeyProfile
    )
    return Signer(certificate: certificate, key: key)
  }

  /// Creates one Security private key.
  private static func makeKey(_ kind: KeyKind) throws -> SecKey {
    let attributes: [CFString: Any]
    switch kind {
    case .ecdsaP256:
      attributes = [
        kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits: Self.ecdsaP256KeySize,
      ]

    case .ecdsaP521:
      attributes = [
        kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits: Self.ecdsaP521KeySize,
      ]

    case .rsa:
      attributes = [
        kSecAttrKeyType: kSecAttrKeyTypeRSA,
        kSecAttrKeySizeInBits: Self.rsaKeySize,
      ]
    }
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error)
    else {
      _ = error?.takeRetainedValue()
      throw Failure.keyCreation
    }
    return key
  }

  /// Constructs one syntactically valid self-signed X.509 certificate.
  private static func certificate(
    for kind: KeyKind,
    key: SecKey,
    profile: CertificateProfile,
    subjectPublicKeyProfile: SubjectPublicKeyProfile,
    issuerName: Data? = nil
  ) throws -> Data {
    let algorithm = Self.certificateAlgorithm(for: kind)
    let name = Self.name("RefineID XMLDSig Test Signer")
    let validity = Self.validity(for: profile)
    var fields = [
      DerEncoder.tlv(
        Self.versionTag,
        DerEncoder.integer(Self.versionThree)
      ),
      DerEncoder.integer(1),
      algorithm,
      issuerName ?? name,
      DerEncoder.sequence([
        Self.generalizedTime(validity.notBefore),
        Self.generalizedTime(validity.notAfter),
      ]),
      name,
      try Self.subjectPublicKeyInfo(
        for: kind,
        key: key,
        profile: subjectPublicKeyProfile
      ),
    ]
    let extensions = Self.certificateExtensions(for: profile)
    if !extensions.isEmpty {
      fields.append(
        DerEncoder.tlv(Self.extensionsTag, DerEncoder.sequence(extensions))
      )
    }
    let tbs = DerEncoder.sequence(fields)
    var error: Unmanaged<CFError>?
    guard
      let signature = SecKeyCreateSignature(
        key,
        Self.certificateSignatureAlgorithm(for: kind),
        tbs as CFData,
        &error
      )
    else {
      _ = error?.takeRetainedValue()
      throw Failure.signatureCreation
    }
    return DerEncoder.sequence([
      tbs,
      algorithm,
      Self.bitString(signature as Data),
    ])
  }

  /// Test certificate validity selected by the signer profile.
  private static func validity(
    for profile: CertificateProfile
  ) -> (notBefore: String, notAfter: String) {
    let notAfter =
      profile == .expiredBeforeIssue
      ? "20260731000000Z"
      : "20300101000000Z"
    return (notBefore: "20250101000000Z", notAfter: notAfter)
  }

  /// BasicConstraints and KeyUsage extensions for one controlled profile.
  private static func certificateExtensions(
    for profile: CertificateProfile
  ) -> [Data] {
    switch profile {
    case .valid, .expiredBeforeIssue:
      return [Self.endEntityExtension, Self.signingKeyUsageExtension]

    case .basicConstraintsAbsent:
      return [Self.signingKeyUsageExtension]

    case .certificateAuthority:
      return [Self.certificateAuthorityExtension, Self.signingKeyUsageExtension]

    case .endEntityPathLength:
      return [Self.endEntityPathLengthExtension, Self.signingKeyUsageExtension]

    case .keyUsageAbsent:
      return [Self.endEntityExtension]

    case .nonSigningKeyUsage:
      return [Self.endEntityExtension, Self.encryptionKeyUsageExtension]
    }
  }

  /// One critical KeyUsage extension.
  private static func keyUsageExtension(firstByte: UInt8) -> Data {
    Self.certificateExtension(
      identifier: Self.keyUsageOid,
      value: DerEncoder.tlv(Self.bitStringTag, Data([0, firstByte]))
    )
  }

  /// One critical X.509 extension around an encoded value.
  private static func certificateExtension(
    identifier: String,
    value: Data
  ) -> Data {
    DerEncoder.sequence([
      DerEncoder.objectIdentifier(identifier),
      DerEncoder.tlv(Self.booleanTag, Data([Self.booleanTrue])),
      DerEncoder.tlv(Self.octetStringTag, value),
    ])
  }

  /// Certificate AlgorithmIdentifier for the generated key family.
  private static func certificateAlgorithm(for kind: KeyKind) -> Data {
    switch kind {
    case .ecdsaP256:
      return DerEncoder.sequence([DerEncoder.objectIdentifier(Self.ecdsaSha256Oid)])

    case .ecdsaP521:
      return DerEncoder.sequence([DerEncoder.objectIdentifier(Self.ecdsaSha512Oid)])

    case .rsa:
      return DerEncoder.sequence([
        DerEncoder.objectIdentifier(Self.rsaSha256Oid),
        DerEncoder.tlv(Self.nullTag, Data()),
      ])
    }
  }

  /// Security signature algorithm matching the certificate key family.
  private static func certificateSignatureAlgorithm(
    for kind: KeyKind
  ) -> SecKeyAlgorithm {
    switch kind {
    case .ecdsaP256:
      return .ecdsaSignatureMessageX962SHA256

    case .ecdsaP521:
      return .ecdsaSignatureMessageX962SHA512

    case .rsa:
      return .rsaSignatureMessagePKCS1v15SHA256
    }
  }

  /// SubjectPublicKeyInfo for one generated public key.
  private static func subjectPublicKeyInfo(
    for kind: KeyKind,
    key: SecKey,
    profile: SubjectPublicKeyProfile
  ) throws -> Data {
    guard let publicKey = SecKeyCopyPublicKey(key) else {
      throw Failure.keyCreation
    }
    var error: Unmanaged<CFError>?
    guard
      let representation = SecKeyCopyExternalRepresentation(publicKey, &error)
    else {
      _ = error?.takeRetainedValue()
      throw Failure.keyCreation
    }
    let algorithm = try Self.subjectPublicKeyAlgorithm(
      kind: kind,
      profile: profile
    )
    let publicKeyBytes = representation as Data
    return DerEncoder.sequence([
      algorithm,
      Self.subjectPublicKeyBitString(publicKeyBytes, profile: profile),
    ])
  }

  /// BIT STRING for a controlled SubjectPublicKeyInfo profile.
  private static func subjectPublicKeyBitString(
    _ publicKey: Data,
    profile: SubjectPublicKeyProfile
  ) -> Data {
    guard profile == .rsaPssUnusedBits else {
      return Self.bitString(publicKey)
    }
    return DerEncoder.tlv(Self.bitStringTag, Data([1]) + publicKey)
  }

  /// X.509 Name with one common-name attribute.
  private static func name(_ commonName: String) -> Data {
    let attribute = DerEncoder.sequence([
      DerEncoder.objectIdentifier(Self.commonNameOid),
      DerEncoder.tlv(Self.utf8StringTag, Data(commonName.utf8)),
    ])
    return DerEncoder.sequence([DerEncoder.setOf([attribute])])
  }

  /// DER GeneralizedTime.
  private static func generalizedTime(_ encoded: String) -> Data {
    DerEncoder.tlv(Self.generalizedTimeTag, Data(encoded.utf8))
  }

  /// DER BIT STRING with no unused bits.
  private static func bitString(_ value: Data) -> Data {
    DerEncoder.tlv(Self.bitStringTag, Data([0]) + value)
  }
}
