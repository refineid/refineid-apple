// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security

/// The two-tier localhost PKI the SCS presents at
/// `https://127.0.0.1:53952` (DVV SCS specification v1.3 §2.3).
///
/// Issuance creates an ephemeral P-256 root authority key in memory,
/// signs one name-constrained root certificate and one short-lived
/// non-CA server leaf around the caller's non-extractable server key,
/// and discards the root private key on return.
public enum ScsLocalhostCertificate {
  /// One freshly minted localhost certificate chain.
  public struct IssuedChain: Equatable, Sendable {
    /// The DER-encoded non-CA server leaf (`CN=127.0.0.1`).
    public let leafDer: Data

    /// The DER-encoded offline root CA certificate.
    public let rootDer: Data

    /// Stores an issued leaf and root pair.
    public init(leafDer: Data, rootDer: Data) {
      self.leafDer = leafDer
      self.rootDer = rootDer
    }
  }

  /// Fields assembled into one X.509 v3 TBSCertificate.
  internal struct TbsFields {
    internal let serialNumber: Data
    internal let issuer: Data
    internal let notBefore: Date
    internal let notAfter: Date
    internal let subject: Data
    internal let subjectPublicKeyInfo: Data
    internal let extensions: Data
  }

  /// The server leaf's common name, fixed by the specification at the
  /// loopback address (v1.3 §2.3).
  public static let commonName = "127.0.0.1"

  /// The offline root authority's common name, distinct from the
  /// server leaf so the chain is never self-issued at the leaf.
  public static let rootCommonName = "RefineID SCS Localhost Root CA"

  internal static var signatureAlgorithm: Data {
    DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.ecdsaWithSha256)])
  }

  /// Wraps a P-256 public key's X9.63 representation as a DER
  /// SubjectPublicKeyInfo.
  public static func subjectPublicKeyInfo(fromX963 representation: Data) -> Data {
    let algorithm = DerEncoder.sequence([
      DerEncoder.objectIdentifier(SignOids.ecPublicKey),
      DerEncoder.objectIdentifier(SignOids.prime256v1),
    ])
    var bits = Data([DerValues.bitStringNoUnusedBits])
    bits.append(representation)
    return DerEncoder.sequence([
      algorithm,
      DerEncoder.tlv(DerValues.tagBitString, bits),
    ])
  }

  /// Mints an offline root CA and a loopback server leaf around
  /// `serverPublicKeyX963`, discarding the root private key on return.
  public static func issueChain(
    serverPublicKeyX963: Data,
    at now: Date
  ) -> IssuedChain? {
    let rootKey = P256.Signing.PrivateKey()
    let rootX963 = rootKey.publicKey.x963Representation
    let rootKeyId = Data(Insecure.SHA1.hash(data: rootX963))
    let leafKeyId = Data(Insecure.SHA1.hash(data: serverPublicKeyX963))
    let notBefore = now.addingTimeInterval(-ScsValues.notBeforeClockSkewSeconds)
    let calendar = Calendar(identifier: .gregorian)
    guard
      let rootNotAfter = calendar.date(
        byAdding: .year, value: ScsValues.rootCertificateValidityYears, to: now),
      let leafNotAfter = calendar.date(
        byAdding: .day, value: ScsValues.leafCertificateValidityDays, to: now)
    else {
      return nil
    }
    let rootName = distinguishedName(commonName: Self.rootCommonName)
    let leafName = distinguishedName(commonName: Self.commonName)
    let rootTbs = tbsCertificate(
      TbsFields(
        serialNumber: randomSerial(),
        issuer: rootName,
        notBefore: notBefore,
        notAfter: rootNotAfter,
        subject: rootName,
        subjectPublicKeyInfo: subjectPublicKeyInfo(fromX963: rootX963),
        extensions: rootExtensions(subjectKeyId: rootKeyId)
      )
    )
    let leafTbs = tbsCertificate(
      TbsFields(
        serialNumber: randomSerial(),
        issuer: rootName,
        notBefore: notBefore,
        notAfter: leafNotAfter,
        subject: leafName,
        subjectPublicKeyInfo: subjectPublicKeyInfo(fromX963: serverPublicKeyX963),
        extensions: leafExtensions(subjectKeyId: leafKeyId, authorityKeyId: rootKeyId)
      )
    )
    guard
      let rootSignature = try? rootKey.signature(for: rootTbs).derRepresentation,
      let leafSignature = try? rootKey.signature(for: leafTbs).derRepresentation
    else {
      return nil
    }
    return IssuedChain(
      leafDer: signedCertificate(tbs: leafTbs, signature: leafSignature),
      rootDer: signedCertificate(tbs: rootTbs, signature: rootSignature)
    )
  }

  /// Whether a stored chain is missing, mismatched, untrusted for
  /// loopback SSL, or within the leaf rotation window at `now`.
  public static func needsRotation(
    leafDer: Data,
    rootDer: Data,
    expectedServerX963: Data,
    at now: Date
  ) -> Bool {
    guard
      let leafFacts = CertificateFacts(der: leafDer),
      let rootFacts = CertificateFacts(der: rootDer),
      !leafFacts.isCertificateAuthority,
      rootFacts.isCertificateAuthority,
      leafFacts.publicKeyBits == expectedServerX963,
      let leafWindow = CertificateValidity.window(inDer: leafDer),
      let rootWindow = CertificateValidity.window(inDer: rootDer),
      now >= leafWindow.notBefore,
      now < rootWindow.notAfter,
      leafWindow.notAfter.timeIntervalSince(now) > ScsValues.leafRotationMarginSeconds,
      let leafCert = SecCertificateCreateWithData(nil, leafDer as CFData),
      let rootCert = SecCertificateCreateWithData(nil, rootDer as CFData)
    else {
      return true
    }
    return !evaluatesLoopbackSsl(leaf: leafCert, root: rootCert, host: Self.commonName, at: now)
      || !evaluatesLoopbackSsl(leaf: leafCert, root: rootCert, host: "localhost", at: now)
  }

  private static func evaluatesLoopbackSsl(
    leaf: SecCertificate,
    root: SecCertificate,
    host: String,
    at now: Date
  ) -> Bool {
    let policy = SecPolicyCreateSSL(true, host as CFString)
    var trust: SecTrust?
    guard
      SecTrustCreateWithCertificates([leaf, root] as CFArray, policy, &trust) == errSecSuccess,
      let trust
    else {
      return false
    }
    guard
      SecTrustSetAnchorCertificates(trust, [root] as CFArray) == errSecSuccess,
      SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
      SecTrustSetVerifyDate(trust, now as CFDate) == errSecSuccess
    else {
      return false
    }
    return SecTrustEvaluateWithError(trust, nil)
  }
}
