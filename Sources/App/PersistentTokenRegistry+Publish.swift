// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) || os(iOS)
  import CardCore
  import CryptoKit
  import CryptoTokenKit
  import Foundation
  import RappEngine
  import Security

  extension PersistentTokenRegistry {
    /// What became of one attempt to offer a borrowed identity.
    internal enum PublishOutcome: Equatable {
      /// The driver holds the certificate; Safari can be offered it.
      case published

      /// A card in a reader outranks the phone; nothing was offered.
      case readerHasPriority

      /// Remote use is off; nothing was offered.
      case remoteUseOff

      /// Nothing was offered: no pairing to bind it to, a certificate
      /// the token cannot use, or no driver.
      case notPublished
    }

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

    internal static func tokenInstanceID(for certificateDER: Data) -> String {
      let hash =
        SHA256.hash(data: certificateDER)
        .map { String(format: "%02x", $0) }
        .joined()
      return PersistentTokenIdentity.instancePrefix + hash
    }

    /// The pairing the published identity was offered for, as the token
    /// configuration the extension reads names it.
    internal static func publishedPairID() -> Data? {
      guard let driver = driverConfiguration else { return nil }
      for configuration in driver.tokenConfigurations.values {
        guard
          let pairing = PersistentTokenPairing(
            configurationData: configuration.configurationData)
        else { continue }
        return pairing.pairID
      }
      return nil
    }

    /// The paired phone's pairing, which an identity published now is
    /// offered for.
    ///
    /// The token configuration names it by its identifier; its keys stay
    /// in `vault`.
    internal static func publishedPairing(in vault: RappDeviceVault) -> PersistentTokenPairing? {
      pairedPhoneID(in: vault).flatMap(PersistentTokenPairing.init(pairID:))
    }

    /// Offers `certificateDER` as the borrowed identity and answers what
    /// became of it.
    ///
    /// The holder line and certificate are set only once the token
    /// configuration exists, so the window never names a person Safari
    /// cannot be offered.
    @discardableResult
    internal static func publish(_ certificateDER: Data) -> PublishOutcome {
      guard Self.dialsPhones else { return .notPublished }
      guard !CardPresence.shared.isReaderCardPresent else {
        #if DEBUG
          print("[persistent-token] suppressed publish: reader card has priority")
          fflush(stdout)
        #endif
        return .readerHasPriority
      }
      guard remoteUseOn else { return .remoteUseOff }
      guard
        let driver = driverConfiguration,
        let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData),
        let profile = CardKeyProfile.resolve(fromCertificate: certificate),
        let (certificateItem, keyItem) = makeKeychainItems(
          for: certificate,
          profile: profile
        ),
        let pairing = publishedPairing(in: RappDeviceVault())
      else {
        return .notPublished
      }

      let instanceID = tokenInstanceID(for: certificateDER)
      if let existing = driver.tokenConfigurations[instanceID],
        existing.configurationData == pairing.configurationData
      {
        shared.certificateDER = certificateDER
        if shared.holderLine == nil {
          shared.holderLine = DistinguishedName.holderLine(fromCertificate: certificateDER)
        }
        #if os(macOS)
          LoginIdentityModel.shared.refresh()
        #endif
        return .published
      }
      for existingID in driver.tokenConfigurations.keys {
        driver.removeTokenConfiguration(for: existingID)
      }
      let configuration = driver.addTokenConfiguration(for: instanceID)
      configuration.configurationData = pairing.configurationData
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
      return publishedCertificateDER() == certificateDER ? .published : .notPublished
    }
  }
#endif
