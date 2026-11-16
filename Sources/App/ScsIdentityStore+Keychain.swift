// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && FEATURE_SCS
  import CardCore
  import CryptoKit
  import Foundation
  import Security

  extension ScsIdentityStore {
    internal static func createNonExtractableServerKey(config: Config) -> SecKey? {
      let attributes: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits as String: Self.keySizeBits,
        kSecAttrLabel as String: config.label,
        kSecAttrIsExtractable as String: false,
        kSecAttrIsSensitive as String: true,
        kSecAttrSynchronizable as String: false,
        kSecPrivateKeyAttrs as String: [
          kSecAttrIsPermanent as String: true,
          kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
          kSecAttrApplicationTag as String: config.serverKeyTag,
        ],
      ]
      return SecKeyCreateRandomKey(attributes as CFDictionary, nil)
    }

    internal static func loadPrivateKey(tag: Data) -> SecKey? {
      let query: [String: Any] = [
        kSecClass as String: kSecClassKey,
        kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        kSecAttrApplicationTag as String: tag,
        kSecMatchLimit as String: kSecMatchLimitOne,
        kSecReturnRef as String: true,
        kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
      ]
      var item: CFTypeRef?
      guard
        SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
        let item,
        CFGetTypeID(item) == SecKeyGetTypeID()
      else {
        return nil
      }
      return unsafeDowncast(item as AnyObject, to: SecKey.self)
    }

    internal static func publicKeyX963(of privateKey: SecKey) -> Data? {
      guard
        let publicKey = SecKeyCopyPublicKey(privateKey),
        let representation = SecKeyCopyExternalRepresentation(publicKey, nil)
      else {
        return nil
      }
      return representation as Data
    }

    internal static func verifiedIdentity(
      forLeaf leafCert: SecCertificate,
      expectedX963: Data
    ) -> SecIdentity? {
      var identity: SecIdentity?
      guard
        SecIdentityCreateWithCertificate(nil, leafCert, &identity) == errSecSuccess,
        let identity
      else {
        return nil
      }
      var pairedKey: SecKey?
      guard
        SecIdentityCopyPrivateKey(identity, &pairedKey) == errSecSuccess,
        let pairedKey,
        publicKeyX963(of: pairedKey) == expectedX963
      else {
        return nil
      }
      return identity
    }

    internal static func storeLeafCertificate(_ cert: SecCertificate, label: String) -> Bool {
      let status = SecItemAdd(
        [
          kSecClass as String: kSecClassCertificate,
          kSecValueRef as String: cert,
          kSecAttrLabel as String: label,
          kSecAttrSynchronizable as String: false,
        ] as CFDictionary,
        nil
      )
      return status == errSecSuccess || status == errSecDuplicateItem
    }

    internal static func requestConstrainedUserTrust(_ rootCert: SecCertificate, label: String) {
      let trustRootResult = Int(SecTrustSettingsResult.trustRoot.rawValue)
      let settings: [[String: Any]] = [
        [
          kSecTrustSettingsPolicy as String: SecPolicyCreateSSL(
            true, ScsLocalhostCertificate.commonName as CFString),
          kSecTrustSettingsPolicyString as String: ScsLocalhostCertificate.commonName,
          kSecTrustSettingsResult as String: trustRootResult,
        ],
        [
          kSecTrustSettingsPolicy as String: SecPolicyCreateSSL(true, "localhost" as CFString),
          kSecTrustSettingsPolicyString as String: "localhost",
          kSecTrustSettingsResult as String: trustRootResult,
        ],
      ]
      let status = SecTrustSettingsSetTrustSettings(rootCert, .user, settings as CFTypeRef)
      if status == errSecSuccess {
        ScsLog.info("identity: constrained localhost root CA trusted for SSL")
      } else {
        ScsLog.error(
          "identity: user trust not granted (\(status)); trust \(label) in Keychain Access")
      }
    }

    internal static func chainRecordQuery(service: String) -> [String: Any] {
      var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: Self.chainAccount,
        kSecAttrSynchronizable as String: false,
      ]
      if let group = CardCredentialStore.sharedKeychainGroup {
        query[kSecAttrAccessGroup as String] = group
        query[kSecUseDataProtectionKeychain as String] = true
      }
      return query
    }

    internal static func saveChainRecord(_ record: ChainRecord, service: String) -> Bool {
      guard let data = try? JSONEncoder().encode(record) else { return false }
      var item = chainRecordQuery(service: service)
      item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      item[kSecValueData as String] = data
      let status = SecItemAdd(item as CFDictionary, nil)
      if status == errSecSuccess { return true }
      if status == errSecDuplicateItem {
        return SecItemUpdate(
          chainRecordQuery(service: service) as CFDictionary,
          [kSecValueData as String: data] as CFDictionary
        ) == errSecSuccess
      }
      return false
    }

    internal static func loadChainRecord(service: String) -> ChainRecord? {
      var query = chainRecordQuery(service: service)
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
      var item: CFTypeRef?
      guard
        SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
        let data = item as? Data
      else {
        return nil
      }
      return try? JSONDecoder().decode(ChainRecord.self, from: data)
    }

    internal static func deleteChainRecord(service: String) {
      _ = SecItemDelete(chainRecordQuery(service: service) as CFDictionary)
    }

    internal static func deleteCertificate(der: Data) {
      guard let cert = SecCertificateCreateWithData(nil, der as CFData) else { return }
      _ = SecItemDelete(
        [kSecClass as String: kSecClassCertificate, kSecValueRef as String: cert] as CFDictionary)
    }

    internal static func deleteCertificatesAndKey(forTag tag: Data, removeTrust: Bool) {
      if let key = loadPrivateKey(tag: tag), let x963 = publicKeyX963(of: key) {
        let keyHash = Data(Insecure.SHA1.hash(data: x963))
        var matches: CFTypeRef?
        let certQuery: [String: Any] = [
          kSecClass as String: kSecClassCertificate,
          kSecAttrPublicKeyHash as String: keyHash,
          kSecMatchLimit as String: kSecMatchLimitAll,
          kSecReturnRef as String: true,
        ]
        if SecItemCopyMatching(certQuery as CFDictionary, &matches) == errSecSuccess,
          let certs = matches as? [Any]
        {
          for item in certs where CFGetTypeID(item as CFTypeRef) == SecCertificateGetTypeID() {
            let cert = unsafeDowncast(item as AnyObject, to: SecCertificate.self)
            if removeTrust {
              _ = SecTrustSettingsRemoveTrustSettings(cert, .user)
            }
            _ = SecItemDelete(
              [kSecClass as String: kSecClassCertificate, kSecValueRef as String: cert]
                as CFDictionary)
          }
        }
      }
      _ = SecItemDelete(
        [kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: tag] as CFDictionary)
    }

    internal static func removeRootTrustAndCertificates(commonName: String) {
      let query: [String: Any] = [
        kSecClass as String: kSecClassCertificate,
        kSecMatchLimit as String: kSecMatchLimitAll,
        kSecReturnRef as String: true,
      ]
      var matches: CFTypeRef?
      guard SecItemCopyMatching(query as CFDictionary, &matches) == errSecSuccess,
        let certs = matches as? [Any]
      else {
        return
      }
      for item in certs where CFGetTypeID(item as CFTypeRef) == SecCertificateGetTypeID() {
        let cert = unsafeDowncast(item as AnyObject, to: SecCertificate.self)
        if let summary = SecCertificateCopySubjectSummary(cert) as String?, summary == commonName {
          _ = SecTrustSettingsRemoveTrustSettings(cert, .user)
          _ = SecItemDelete(
            [kSecClass as String: kSecClassCertificate, kSecValueRef as String: cert]
              as CFDictionary)
        }
      }
    }

    internal static func removeLegacyV1Identity() {
      deleteCertificatesAndKey(forTag: legacyV1KeyTag, removeTrust: true)
      removeRootTrustAndCertificates(commonName: ScsLocalhostCertificate.rootCommonName)
    }
  }
#endif
