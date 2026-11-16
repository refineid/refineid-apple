// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoKit
import Foundation
import Security
import Testing

/// The two-tier localhost PKI the SCS presents (DVV SCS specification
/// v1.3 §2.3): an offline name-constrained root CA and a short-lived
/// non-CA server leaf.
@Suite
internal struct ScsLocalhostCertificateTests {
  @Test
  internal func issuesDistinctRootAuthorityAndNonCaServerLeaf() throws {
    let serverKey = P256.Signing.PrivateKey()
    let now = Date()
    let chain = try #require(
      ScsLocalhostCertificate.issueChain(
        serverPublicKeyX963: serverKey.publicKey.x963Representation,
        at: now
      )
    )
    let leafFacts = try #require(CertificateFacts(der: chain.leafDer))
    let rootFacts = try #require(CertificateFacts(der: chain.rootDer))
    #expect(!leafFacts.isCertificateAuthority)
    #expect(!leafFacts.isSelfIssued)
    #expect(rootFacts.isCertificateAuthority)
    #expect(rootFacts.isSelfIssued)
    #expect(leafFacts.issuerName == rootFacts.subjectName)
    #expect(leafFacts.publicKeyBits == serverKey.publicKey.x963Representation)
    #expect(rootFacts.publicKeyBits != serverKey.publicKey.x963Representation)

    let leafCert = try #require(SecCertificateCreateWithData(nil, chain.leafDer as CFData))
    let rootCert = try #require(SecCertificateCreateWithData(nil, chain.rootDer as CFData))
    var leafCn: CFString?
    var rootCn: CFString?
    _ = SecCertificateCopyCommonName(leafCert, &leafCn)
    _ = SecCertificateCopyCommonName(rootCert, &rootCn)
    #expect(leafCn as String? == "127.0.0.1")
    #expect(rootCn as String? == ScsLocalhostCertificate.rootCommonName)
  }

  @Test
  internal func chainValidatesForLoopbackSslOnly() throws {
    let serverKey = P256.Signing.PrivateKey()
    let now = Date()
    let chain = try #require(
      ScsLocalhostCertificate.issueChain(
        serverPublicKeyX963: serverKey.publicKey.x963Representation,
        at: now
      )
    )
    let leaf = try #require(SecCertificateCreateWithData(nil, chain.leafDer as CFData))
    let root = try #require(SecCertificateCreateWithData(nil, chain.rootDer as CFData))

    for host in ["127.0.0.1", "localhost"] {
      var trust: SecTrust?
      #expect(
        SecTrustCreateWithCertificates(
          [leaf, root] as CFArray,
          SecPolicyCreateSSL(true, host as CFString),
          &trust
        ) == errSecSuccess
      )
      let unwrapped = try #require(trust)
      #expect(SecTrustSetAnchorCertificates(unwrapped, [root] as CFArray) == errSecSuccess)
      #expect(SecTrustSetAnchorCertificatesOnly(unwrapped, true) == errSecSuccess)
      #expect(SecTrustSetVerifyDate(unwrapped, now as CFDate) == errSecSuccess)
      #expect(SecTrustEvaluateWithError(unwrapped, nil))
    }

    var wrongHostTrust: SecTrust?
    #expect(
      SecTrustCreateWithCertificates(
        [leaf, root] as CFArray,
        SecPolicyCreateSSL(true, "evil.example" as CFString),
        &wrongHostTrust
      ) == errSecSuccess
    )
    let wrongUnwrapped = try #require(wrongHostTrust)
    _ = SecTrustSetAnchorCertificates(wrongUnwrapped, [root] as CFArray)
    _ = SecTrustSetAnchorCertificatesOnly(wrongUnwrapped, true)
    _ = SecTrustSetVerifyDate(wrongUnwrapped, now as CFDate)
    #expect(!SecTrustEvaluateWithError(wrongUnwrapped, nil))
  }

  @Test
  internal func rotationTriggersNearLeafExpiryOrOnKeyMismatch() throws {
    let serverKey = P256.Signing.PrivateKey()
    let otherKey = P256.Signing.PrivateKey()
    let start = Date()
    let chain = try #require(
      ScsLocalhostCertificate.issueChain(
        serverPublicKeyX963: serverKey.publicKey.x963Representation,
        at: start
      )
    )
    #expect(
      !ScsLocalhostCertificate.needsRotation(
        leafDer: chain.leafDer,
        rootDer: chain.rootDer,
        expectedServerX963: serverKey.publicKey.x963Representation,
        at: start.addingTimeInterval(86_400 * 300)
      )
    )
    #expect(
      ScsLocalhostCertificate.needsRotation(
        leafDer: chain.leafDer,
        rootDer: chain.rootDer,
        expectedServerX963: serverKey.publicKey.x963Representation,
        at: start.addingTimeInterval(86_400 * 380)
      )
    )
    #expect(
      ScsLocalhostCertificate.needsRotation(
        leafDer: chain.leafDer,
        rootDer: chain.rootDer,
        expectedServerX963: otherKey.publicKey.x963Representation,
        at: start
      )
    )
  }
}
