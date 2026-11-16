// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && FEATURE_SCS
  import CardCore
  import Foundation
  import Security

  /// Keychain-backed TLS serving chain for the localhost SCS (DVV SCS
  /// specification v1.3 §2.3).
  ///
  /// Mints a non-extractable P-256 server key plus an offline-root and
  /// short-lived leaf chain, binds lookup to our application tag and
  /// key public-key bytes rather than CN matching, constrains root
  /// user trust to SSL on `127.0.0.1` and `localhost`, rotates expiring
  /// leaves, and removes key, certificates, and trust on opt-out.
  internal enum ScsIdentityStore {
    /// Coordinates isolating production storage from test storage.
    internal struct Config: Sendable {
      internal let serverKeyTag: Data
      internal let chainService: String
      internal let label: String
      internal let applyUserTrust: Bool
    }

    /// Ready-to-serve leaf identity paired with its issuing root CA.
    internal struct ServingChain {
      internal let identity: SecIdentity
      internal let rootCertificate: SecCertificate
    }

    internal struct ChainRecord: Codable {
      internal let leafDer: Data
      internal let rootDer: Data
    }

    internal static let productionConfig = Config(
      serverKeyTag: Data("fi.refineid.scs.localhost.server.v2".utf8),
      chainService: "fi.refineid.scs.localhost.chain.v2",
      label: "RefineID SCS localhost",
      applyUserTrust: true
    )

    internal static let legacyV1KeyTag = Data("fi.refineid.scs.localhost".utf8)
    internal static let chainAccount = "active"
    internal static let keySizeBits = 256

    /// Obtains or rotates the production localhost serving chain.
    internal static func obtain() -> ServingChain? {
      removeLegacyV1Identity()
      return obtain(config: productionConfig, at: Date())
    }

    /// Removes the production localhost key, certificates, chain
    /// record, and user-domain SSL trust settings.
    internal static func removeAll() {
      removeLegacyV1Identity()
      removeChain(config: productionConfig)
    }

    /// Obtains or rotates the chain in `config` at `now`.
    internal static func obtain(config: Config, at now: Date) -> ServingChain? {
      if let existing = existingChain(config: config, at: now) {
        return existing
      }
      return mintChain(config: config, at: now)
    }

    /// Deletes key, certificates, chain record, and optional user trust
    /// for `config`.
    internal static func removeChain(config: Config) {
      if let record = loadChainRecord(service: config.chainService) {
        if config.applyUserTrust,
          let root = SecCertificateCreateWithData(nil, record.rootDer as CFData)
        {
          _ = SecTrustSettingsRemoveTrustSettings(root, .user)
        }
        deleteCertificate(der: record.leafDer)
        deleteCertificate(der: record.rootDer)
      }
      if config.applyUserTrust {
        removeRootTrustAndCertificates(commonName: ScsLocalhostCertificate.rootCommonName)
      }
      deleteCertificatesAndKey(forTag: config.serverKeyTag, removeTrust: config.applyUserTrust)
      deleteChainRecord(service: config.chainService)
    }

    private static func existingChain(config: Config, at now: Date) -> ServingChain? {
      guard
        let serverKey = loadPrivateKey(tag: config.serverKeyTag),
        let serverX963 = publicKeyX963(of: serverKey),
        let record = loadChainRecord(service: config.chainService),
        !ScsLocalhostCertificate.needsRotation(
          leafDer: record.leafDer,
          rootDer: record.rootDer,
          expectedServerX963: serverX963,
          at: now
        ),
        let leafCert = SecCertificateCreateWithData(nil, record.leafDer as CFData),
        let rootCert = SecCertificateCreateWithData(nil, record.rootDer as CFData),
        let identity = verifiedIdentity(forLeaf: leafCert, expectedX963: serverX963)
      else {
        return nil
      }
      return ServingChain(identity: identity, rootCertificate: rootCert)
    }

    private static func mintChain(config: Config, at now: Date) -> ServingChain? {
      removeChain(config: config)
      guard
        let serverKey = createNonExtractableServerKey(config: config),
        let serverX963 = publicKeyX963(of: serverKey),
        let issued = ScsLocalhostCertificate.issueChain(serverPublicKeyX963: serverX963, at: now),
        let leafCert = SecCertificateCreateWithData(nil, issued.leafDer as CFData),
        let rootCert = SecCertificateCreateWithData(nil, issued.rootDer as CFData)
      else {
        ScsLog.error("identity: localhost chain generation failed")
        removeChain(config: config)
        return nil
      }
      guard storeLeafCertificate(leafCert, label: config.label),
        saveChainRecord(
          ChainRecord(leafDer: issued.leafDer, rootDer: issued.rootDer),
          service: config.chainService
        ),
        let identity = verifiedIdentity(forLeaf: leafCert, expectedX963: serverX963)
      else {
        ScsLog.error("identity: localhost chain persistence failed")
        removeChain(config: config)
        return nil
      }
      if config.applyUserTrust {
        requestConstrainedUserTrust(rootCert, label: config.label)
      }
      return ServingChain(identity: identity, rootCertificate: rootCert)
    }
  }
#endif
