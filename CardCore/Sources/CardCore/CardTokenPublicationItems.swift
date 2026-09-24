// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) || os(iOS)
  import CryptoTokenKit
  import Foundation
  import Security

  /// Builds CryptoTokenKit keychain items for publishing card identities.
  public enum CardTokenPublicationItems {
    /// Safari's chooser title, matching the local reader token.
    public static var authenticationLabel: String {
      String(localized: "Basic (PIN 1)")
    }

    /// Builds the keychain items published for browser authentication.
    public static func makeItems(
      leaf: SecCertificate,
      profile: CardKeyProfile,
      issuerDER: Data?,
      requiresPinConstraint: Bool
    ) -> [TKTokenKeychainItem] {
      guard
        let certificateItem = TKTokenKeychainCertificate(
          certificate: leaf,
          objectID: CardTokenNamespace.authKeyObjectID
        ),
        let keyItem = TKTokenKeychainKey(
          certificate: leaf,
          objectID: CardTokenNamespace.authKeyObjectID
        )
      else {
        return []
      }

      certificateItem.label = authenticationLabel
      keyItem.label = authenticationLabel
      keyItem.keyType = profile.keyType
      keyItem.keySizeInBits = profile.keySizeInBits
      keyItem.canSign = true
      keyItem.canDecrypt = false
      keyItem.canPerformKeyExchange = false
      keyItem.isSuitableForLogin = true

      if requiresPinConstraint {
        // swiftlint:disable:next legacy_objc_type
        let signOperationKey = NSNumber(value: TKTokenOperation.signData.rawValue)
        keyItem.constraints = [signOperationKey: CardTokenNamespace.pin1SignDataConstraint]
      }

      var items: [TKTokenKeychainItem] = [certificateItem, keyItem]
      if let issuerDER,
        let issuer = SecCertificateCreateWithData(nil, issuerDER as CFData),
        let issuerItem = TKTokenKeychainCertificate(
          certificate: issuer,
          objectID: CardTokenNamespace.issuerCertificateObjectID
        )
      {
        items.append(issuerItem)
      }
      return items
    }
  }
#endif
