// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security

/// Dynamic in-memory cache and accessors for FINEID root and intermediate CA certificates.
///
/// Rather than bundling static CA certificate files in the application, certificates
/// are fetched directly from the smart card (`EF.4334` for Root CA, `EF.4336` for
/// Intermediate CA) or received over the RAPP protocol when an application starts.
///
/// Thread safety is ensured via an internal `NSLock`.
public final class TrustRootsCache: @unchecked Sendable {
  /// Shared global instance.
  public static let shared = TrustRootsCache()

  /// Well-known pinned DVV Gov. Root CA - G3 RSA SHA-256 fingerprint.
  public static let pinnedDvvG3RsaSha256: [UInt8] = FineidValues.pinnedDvvG3RsaSha256

  /// Well-known pinned DVV Gov. Root CA - G3 ECC SHA-256 fingerprint.
  public static let pinnedDvvG3EccSha256: [UInt8] = FineidValues.pinnedDvvG3EccSha256

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

  /// Query coordinates for a persistent CA certificate item.
  private static func query(account: String) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: false,
    ]
    if KeychainPlatform.usesDataProtection {
      query[kSecUseDataProtectionKeychain as String] = true
      query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    }
    return query
  }

  /// Saves a newly registered certificate to persistent storage if unexpired.
  private static func persistCertificate(_ der: Data) {
    if let window = CertificateValidity.window(inDer: der), window.notAfter < Date() {
      return
    }
    let fingerprint = Data(SHA256.hash(data: der))
    let account = fingerprint.map { String(format: "%02x", $0) }.joined()

    if TestCredentialEnvironment.isTestMode {
      TestCredentialEnvironment.storeTrustedCa(der, account: account)
      return
    }

    var coordinates = query(account: account)
    coordinates[kSecValueData as String] = der
    let status = SecItemAdd(coordinates as CFDictionary, nil)
    if status == errSecDuplicateItem {
      let updateQuery = query(account: account)
      let replacement = [kSecValueData as String: der]
      _ = SecItemUpdate(updateQuery as CFDictionary, replacement as CFDictionary)
    }
  }

  /// Registers an on-card issuing intermediate CA certificate.
  public func register(_ certificateDER: Data) {
    lock.lock()
    defer { lock.unlock() }
    intermediateCaDER = certificateDER
    indexCertificate(certificateDER)
    Self.persistCertificate(certificateDER)
  }

  /// Registers an on-card root CA certificate.
  public func registerRoot(_ certificateDER: Data) {
    lock.lock()
    defer { lock.unlock() }
    rootCaDER = certificateDER
    indexCertificate(certificateDER)
    Self.persistCertificate(certificateDER)
  }

  /// Registers an extra CA certificate.
  public func registerExtra(_ certificateDER: Data) {
    lock.lock()
    defer { lock.unlock() }
    extraCasDER.append(certificateDER)
    indexCertificate(certificateDER)
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

  /// Registers card-supplied CA certificates when the cache holds no
  /// issuer for `leafDER`, and answers the match.
  ///
  /// Evidence collection ends only at an explicitly approved anchor,
  /// and only this process's cache can supply it: registrations made
  /// in another process never arrive here.
  public func ensureIssuer(
    for leafDER: Data,
    cardIssuer: Data?,
    cardRoot: Data?
  ) -> Data? {
    if let cached = der(matching: leafDER) {
      return cached
    }
    if let cardIssuer {
      register(cardIssuer)
    }
    if rootCertificate == nil, let cardRoot {
      registerRoot(cardRoot)
    }
    return der(matching: leafDER)
  }

  /// Checks whether a SHA-256 fingerprint matches any cached CA certificate.
  public func containsFingerprint(_ fingerprint: Data) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return certsByFingerprint[fingerprint] != nil
  }

  /// Checks whether a SHA-256 fingerprint matches a trusted root CA.
  public func isTrustedRoot(fingerprint: Data) -> Bool {
    if containsFingerprint(fingerprint) {
      return true
    }
    let rsa = Data(Self.pinnedDvvG3RsaSha256)
    let ecc = Data(Self.pinnedDvvG3EccSha256)
    return fingerprint == rsa || fingerprint == ecc
  }

  /// Resets the cache (primarily for tests).
  public func reset() {
    lock.lock()
    defer { lock.unlock() }
    rootCaDER = nil
    intermediateCaDER = nil
    extraCasDER.removeAll()
    certsBySubject.removeAll()
    certsByFingerprint.removeAll()
    if TestCredentialEnvironment.isTestMode {
      TestCredentialEnvironment.forgetAllTrustedCas()
    }
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
  private func loadValidCertificate(_ der: Data) {
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

  /// Loads persisted certificates on startup, purging any expired ones.
  private func loadPersistedCas() {
    let now = Date()
    if TestCredentialEnvironment.isTestMode {
      let items = TestCredentialEnvironment.allTrustedCas()
      for (account, data) in items {
        if let window = CertificateValidity.window(inDer: data), window.notAfter < now {
          TestCredentialEnvironment.deleteTrustedCa(account: account)
          continue
        }
        loadValidCertificate(data)
      }
      return
    }

    var search: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecMatchLimit as String: kSecMatchLimitAll,
      kSecReturnData as String: true,
      kSecReturnAttributes as String: true,
      kSecAttrSynchronizable as String: false,
    ]
    if KeychainPlatform.usesDataProtection {
      search[kSecUseDataProtectionKeychain as String] = true
    }
    var result: CFTypeRef?
    guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess,
      let items = result as? [[String: Any]]
    else {
      return
    }

    for item in items {
      guard
        let account = item[kSecAttrAccount as String] as? String,
        let data = item[kSecValueData as String] as? Data
      else {
        continue
      }
      if let window = CertificateValidity.window(inDer: data), window.notAfter < now {
        let deleteQuery = Self.query(account: account)
        SecItemDelete(deleteQuery as CFDictionary)
        continue
      }
      loadValidCertificate(data)
    }
  }
}
