// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)
  import CardCore
  import Foundation
  import Security
  import Testing

  @testable import RefineIDTestHost

  @Suite("Localhost SCS identity store", .serialized)
  internal struct ScsIdentityStoreTests {
    #if FEATURE_SCS
      @Test
      internal func mintsNonExtractableKeyReusesRotatesAndCleansUp() throws {
        let config = ScsIdentityStore.Config(
          serverKeyTag: Data("fi.refineid.tests.scs.key.\(UUID().uuidString)".utf8),
          chainService: "fi.refineid.tests.scs.chain.\(UUID().uuidString)",
          label: "RefineID SCS test",
          applyUserTrust: false
        )
        defer { ScsIdentityStore.removeChain(config: config) }

        let now = Date()
        let minted = try #require(ScsIdentityStore.obtain(config: config, at: now))
        var privateKey: SecKey?
        #expect(SecIdentityCopyPrivateKey(minted.identity, &privateKey) == errSecSuccess)
        let unwrappedKey = try #require(privateKey)
        let ourX963 = try #require(ScsIdentityStore.publicKeyX963(of: unwrappedKey))

        var exported: CFData?
        #expect(SecItemExport(unwrappedKey, .formatOpenSSL, [], nil, &exported) != errSecSuccess)

        let reused = try #require(
          ScsIdentityStore.obtain(config: config, at: now.addingTimeInterval(60)))
        var reusedKey: SecKey?
        #expect(SecIdentityCopyPrivateKey(reused.identity, &reusedKey) == errSecSuccess)
        #expect(ScsIdentityStore.publicKeyX963(of: try #require(reusedKey)) == ourX963)

        let rotated = try #require(
          ScsIdentityStore.obtain(config: config, at: now.addingTimeInterval(86_400 * 380)))
        var rotatedKey: SecKey?
        #expect(SecIdentityCopyPrivateKey(rotated.identity, &rotatedKey) == errSecSuccess)
        #expect(ScsIdentityStore.publicKeyX963(of: try #require(rotatedKey)) != ourX963)

        ScsIdentityStore.removeChain(config: config)
        #expect(ScsIdentityStore.loadPrivateKey(tag: config.serverKeyTag) == nil)
        #expect(ScsIdentityStore.loadChainRecord(service: config.chainService) == nil)
      }

      @Test
      internal func ignoresPlantedForeignLoopbackCommonNameIdentity() throws {
        let config = ScsIdentityStore.Config(
          serverKeyTag: Data("fi.refineid.tests.scs.own.\(UUID().uuidString)".utf8),
          chainService: "fi.refineid.tests.scs.ownchain.\(UUID().uuidString)",
          label: "RefineID SCS test",
          applyUserTrust: false
        )
        let foreignTag = Data("fi.refineid.tests.scs.foreign.\(UUID().uuidString)".utf8)
        var foreignCert: SecCertificate?
        defer {
          ScsIdentityStore.removeChain(config: config)
          _ = SecItemDelete(
            [kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: foreignTag]
              as CFDictionary)
          if let foreignCert {
            _ = SecItemDelete(
              [kSecClass as String: kSecClassCertificate, kSecValueRef as String: foreignCert]
                as CFDictionary)
          }
        }
        let foreignKey = try #require(
          SecKeyCreateRandomKey(
            [
              kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
              kSecAttrKeySizeInBits as String: 256,
              kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: foreignTag,
              ],
            ] as CFDictionary,
            nil
          )
        )
        let foreignX963 = try #require(ScsIdentityStore.publicKeyX963(of: foreignKey))
        let foreignIssued = try #require(
          ScsLocalhostCertificate.issueChain(serverPublicKeyX963: foreignX963, at: Date()))
        foreignCert = SecCertificateCreateWithData(nil, foreignIssued.leafDer as CFData)
        if let foreignCert {
          _ = SecItemAdd(
            [kSecClass as String: kSecClassCertificate, kSecValueRef as String: foreignCert]
              as CFDictionary,
            nil
          )
        }
        let minted = try #require(ScsIdentityStore.obtain(config: config, at: Date()))
        var ourKey: SecKey?
        #expect(SecIdentityCopyPrivateKey(minted.identity, &ourKey) == errSecSuccess)
        #expect(ScsIdentityStore.publicKeyX963(of: try #require(ourKey)) != foreignX963)
      }
    #else
      @Test
      internal func identityStoreIsExcludedWhenFeatureFlagIsOff() {
        #expect(NSClassFromString("RefineIDTestHost.ScsIdentityStore") == nil)
      }
    #endif
  }
#endif
