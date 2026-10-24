// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security

/// Dynamic in-memory cache and accessors for FINEID root and intermediate CA certificates.
///
/// Certificates are read from the smart card (`EF.4334` for Root CA, `EF.4336` for
/// Intermediate CA) or received over the RAPP protocol when an application starts.
/// Valid certificates are persisted in Keychain or test store.
///
/// Thread safety is ensured via an internal `NSLock`.
public final class TrustRootsCache: @unchecked Sendable {
  /// Shared global instance.
  public static let shared = TrustRootsCache()

  /// Keychain service the trusted CA certificates live under.
  public static let service = "fi.refineid.trust"

  private let lock = NSLock()
  private var rootCaDER: Data?
  private var intermediateCaDER: Data?
  private var extraCasDER: [Data] = []
  private var certsBySubject: [Data: Data] = [:]
  private var certsByFingerprint: [Data: Data] = [:]

  /// Returns the cached intermediate CA in DER format, if available.
  public var intermediateCertificate: Data? {
    lock.lock()
    defer { lock.unlock() }
    return intermediateCaDER
  }

  /// Returns the cached root CA in DER format, if available.
  public var rootCertificate: Data? {
    lock.lock()
    defer { lock.unlock() }
    return rootCaDER
  }

  /// Returns all cached certificates.
  public var allCertificates: [Data] {
    lock.lock()
    defer { lock.unlock() }
    return lockedAllCertificates()
  }

  /// Creates a new trust roots cache and loads valid persisted CAs.
  public init() {
    loadPersistedCas()
  }

  /// Determines whether a certificate is self-signed (root CA).
  private static func isSelfSigned(_ der: Data) -> Bool {
    guard
      let cert = SecCertificateCreateWithData(nil, der as CFData),
      let subject = SecCertificateCopyNormalizedSubjectSequence(cert) as Data?,
      let issuer = SecCertificateCopyNormalizedIssuerSequence(cert) as Data?
    else {
      return false
    }
    return subject == issuer
  }

  /// Registers an on-card issuing intermediate CA certificate.
  ///
  /// In-memory indexing unconditionally holds the certificate to support
  /// runtime chain matching for non-conforming card certs, while persistence
  /// independently validates that it meets the persistence policy.
  public func register(_ certificateDER: Data) {
    lock.lock()
    intermediateCaDER = certificateDER
    indexCertificate(certificateDER)
    lock.unlock()
    Self.persistCertificate(certificateDER)
  }

  /// Registers an on-card root CA certificate.
  ///
  /// In-memory indexing unconditionally holds the certificate, while persistence
  /// independently validates that it meets the persistence policy.
  public func registerRoot(_ certificateDER: Data) {
    lock.lock()
    rootCaDER = certificateDER
    indexCertificate(certificateDER)
    lock.unlock()
    Self.persistCertificate(certificateDER)
  }

  /// Registers an extra CA certificate.
  ///
  /// In-memory indexing unconditionally holds the certificate, while persistence
  /// independently validates that it meets the persistence policy.
  public func registerExtra(_ certificateDER: Data) {
    lock.lock()
    extraCasDER.append(certificateDER)
    indexCertificate(certificateDER)
    lock.unlock()
    Self.persistCertificate(certificateDER)
  }

  /// Returns the matching cached intermediate/root certificate for a given leaf.
  public func der(matching leafDER: Data) -> Data? {
    guard
      let leaf = SecCertificateCreateWithData(nil, leafDER as CFData),
      let issuer = SecCertificateCopyNormalizedIssuerSequence(leaf) as Data?
    else {
      return nil
    }

    lock.lock()
    defer { lock.unlock() }

    if let direct = certsBySubject[issuer] {
      return direct
    }

    for candidate in lockedAllCertificates() {
      guard
        let cert = SecCertificateCreateWithData(nil, candidate as CFData),
        let subject = SecCertificateCopyNormalizedSubjectSequence(cert) as Data?
      else {
        continue
      }
      if subject == issuer {
        certsBySubject[issuer] = candidate
        return candidate
      }
    }
    return nil
  }

  /// The issuing certificate for `leafDER`, asking the card only for
  /// what this cache cannot answer.
  ///
  /// A cached issuer answers without `cardIssuer` being called. A root is
  /// read with `cardRoot` only when no unexpired cached root issued the
  /// issuing certificate, and is admitted only when it is self-signed, a
  /// certificate authority within its validity, and the verified issuer of
  /// that issuing certificate. An admitted root is persisted and is not
  /// asked for again until it expires.
  public func issuer(
    for leafDER: Data,
    cardIssuer: () -> Data?,
    cardRoot: () -> Data?
  ) -> Data? {
    dropExpired(at: Date())
    let issuer: Data
    if let cached = der(matching: leafDER) {
      issuer = cached
    } else if let read = cardIssuer() {
      register(read)
      issuer = read
    } else {
      return nil
    }
    learnRoot(above: issuer, cardRoot: cardRoot)
    return issuer
  }

  /// Reads the root above `issuerDER` with `cardRoot` only when no
  /// unexpired cached root issued it, and admits what was read only when
  /// it is self-signed, a certificate authority within its validity, and
  /// the verified issuer of `issuerDER`.
  public func learnRoot(above issuerDER: Data, cardRoot: () -> Data?) {
    dropExpired(at: Date())
    guard
      !Self.isSelfSigned(issuerDER),
      der(matching: issuerDER) == nil,
      let root = cardRoot(),
      Self.isSelfSigned(root),
      Self.meetsPersistencePolicy(root),
      CertificateIssuer.isDirectlyIssued(issuerDER, by: root, at: Date())
    else {
      return
    }
    registerRoot(root)
  }

  /// Forgets every cached certificate whose validity ended before `now`,
  /// in memory and in persistent storage.
  ///
  /// Expiry is the only thing that retires a cached certificate.
  internal func dropExpired(at now: Date) {
    lock.lock()
    let expired = lockedAllCertificates().filter { der in
      !Self.isUnexpired(der, at: now)
    }
    for der in expired {
      if rootCaDER == der { rootCaDER = nil }
      if intermediateCaDER == der { intermediateCaDER = nil }
      extraCasDER.removeAll { $0 == der }
      certsByFingerprint[Data(SHA256.hash(data: der))] = nil
      certsBySubject = certsBySubject.filter { $0.value != der }
    }
    lock.unlock()
    for der in expired {
      Self.deletePersistedCertificate(der)
    }
  }

  /// Checks whether a SHA-256 fingerprint matches any cached CA certificate.
  public func containsFingerprint(_ fingerprint: Data) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return certsByFingerprint[fingerprint] != nil
  }

  /// Checks whether a SHA-256 fingerprint matches a trusted root CA.
  public func isTrustedRoot(fingerprint: Data) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if let rootDer = rootCaDER, Data(SHA256.hash(data: rootDer)) == fingerprint {
      return true
    }
    if let certDer = certsByFingerprint[fingerprint], Self.isSelfSigned(certDer) {
      return true
    }
    return false
  }

  /// Completely clears in-memory and persistent CA storage.
  public func forgetAll() {
    lock.lock()
    rootCaDER = nil
    intermediateCaDER = nil
    extraCasDER.removeAll()
    certsBySubject.removeAll()
    certsByFingerprint.removeAll()
    lock.unlock()

    Self.deletePersistentCas()
  }

  /// Resets the cache (primarily for tests).
  public func reset() {
    forgetAll()
  }

  /// All cached certificates.
  ///
  /// Call only with `lock` already held; `NSLock` is not recursive,
  /// so locked callers must not re-lock.
  private func lockedAllCertificates() -> [Data] {
    var list: [Data] = []
    if let root = rootCaDER { list.append(root) }
    if let inter = intermediateCaDER { list.append(inter) }
    list.append(contentsOf: extraCasDER)
    return list
  }

  /// Indexes a certificate by its normalized subject sequence and SHA-256 fingerprint.
  private func indexCertificate(_ der: Data) {
    let fingerprint = Data(SHA256.hash(data: der))
    certsByFingerprint[fingerprint] = der

    guard
      let cert = SecCertificateCreateWithData(nil, der as CFData),
      let subject = SecCertificateCopyNormalizedSubjectSequence(cert) as Data?
    else {
      return
    }
    certsBySubject[subject] = der
  }

  /// Loads an unexpired certificate into the memory caches.
  internal func loadValidCertificate(_ der: Data) {
    indexCertificate(der)
    if Self.isSelfSigned(der) {
      if rootCaDER == nil {
        rootCaDER = der
      }
    } else {
      if intermediateCaDER == nil {
        intermediateCaDER = der
      } else if !extraCasDER.contains(der) {
        extraCasDER.append(der)
      }
    }
  }
}
