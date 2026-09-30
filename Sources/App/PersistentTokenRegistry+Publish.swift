// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) || os(iOS)
  import CardCore
  import CryptoKit
  import CryptoTokenKit
  import Foundation
  import RappEngine
  import Security

  extension PersistentTokenRegistry {
    /// The certificate this driver is currently offering, if any.
    internal static func publishedCertificateDER() -> Data? {
      guard let driver = driverConfiguration else { return nil }
      for configuration in driver.tokenConfigurations.values {
        guard
          let item = try? configuration.certificate(
            for: PersistentTokenIdentity.certificateObjectID
          )
        else {
          continue
        }
        return item.data
      }
      return nil
    }

    internal static func makeKeychainItems(
      for certificate: SecCertificate,
      profile: CardKeyProfile
    ) -> (TKTokenKeychainCertificate, TKTokenKeychainKey)? {
      guard
        let certificateItem = TKTokenKeychainCertificate(
          certificate: certificate,
          objectID: PersistentTokenIdentity.certificateObjectID
        ),
        let keyItem = TKTokenKeychainKey(
          certificate: certificate,
          objectID: PersistentTokenIdentity.keyObjectID
        )
      else {
        return nil
      }
      certificateItem.label = authenticationLabel
      keyItem.label = authenticationLabel
      keyItem.keyType = profile.keyType
      keyItem.keySizeInBits = profile.keySizeInBits
      keyItem.canSign = true
      keyItem.canDecrypt = false
      keyItem.canPerformKeyExchange = false
      keyItem.isSuitableForLogin = true
      return (certificateItem, keyItem)
    }

    internal static func tokenInstanceID(
      for certificateDER: Data,
      cardSerial: String?
    ) -> String {
      if let cardSerial, !cardSerial.isEmpty {
        return PersistentTokenIdentity.instancePrefix + cardSerial.lowercased()
      }
      let hash =
        SHA256.hash(data: certificateDER)
        .map { String(format: "%02x", $0) }
        .joined()
      return PersistentTokenIdentity.instancePrefix + hash
    }

    internal static func activePairConfigurationData() -> Data? {
      let vault = RappDeviceVault()
      let pairIDs = (try? vault.activePairIDs()) ?? []
      guard let pairID = (try? vault.selectedPairID()) ?? pairIDs.first,
        let pair = try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault)
      else {
        return nil
      }
      return try? pair.encodedBytes()
    }

    internal static func publish(_ certificateDER: Data) {
      publish(certificateDER, cardSerial: nil)
    }

    internal static func publish(_ certificateDER: Data, cardSerial: String?) {
      guard Self.isRemoteCardEnabled else { return }
      guard !CardPresence.shared.isReaderCardPresent else {
        #if DEBUG
          print("[persistent-token] suppressed publish: reader card has priority")
          fflush(stdout)
        #endif
        return
      }
      guard
        let driver = driverConfiguration,
        let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData),
        let profile = CardKeyProfile.resolve(fromCertificate: certificate),
        let (certificateItem, keyItem) = makeKeychainItems(
          for: certificate,
          profile: profile
        ),
        let pairBytes = activePairConfigurationData()
      else {
        return
      }

      let instanceID = tokenInstanceID(for: certificateDER, cardSerial: cardSerial)
      if let existing = driver.tokenConfigurations[instanceID],
        existing.configurationData == pairBytes
      {
        shared.certificateDER = certificateDER
        if shared.holderLine == nil {
          shared.holderLine = DistinguishedName.holderLine(fromCertificate: certificateDER)
        }
        #if os(macOS)
          LoginIdentityModel.shared.refresh()
        #endif
        return
      }
      for existingID in driver.tokenConfigurations.keys {
        driver.removeTokenConfiguration(for: existingID)
      }
      let configuration = driver.addTokenConfiguration(for: instanceID)
      configuration.configurationData = pairBytes
      configuration.keychainItems = [certificateItem, keyItem]
      shared.certificateDER = certificateDER
      shared.holderLine = DistinguishedName.holderLine(fromCertificate: certificateDER)
      #if os(macOS)
        LoginIdentityModel.shared.refresh()
      #endif
      #if DEBUG
        print("[persistent-token] published \(instanceID)")
        fflush(stdout)
      #endif
    }
  }
#endif
