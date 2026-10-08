// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// The KC2 key schedule: the Noise pre-shared key and both confirmation tags.
internal struct CpaceKc2Keys {
  internal let presharedKey: Data
  internal let initiatorTag: Data
  internal let responderTag: Data

  /// RFC 5869 HKDF-SHA-512 keyed by the transcript hash over the ISK.
  internal init(intermediateSessionKey: Data, transcriptHash: Data) {
    let pseudorandomKey = Data(
      HMAC<SHA512>.authenticationCode(
        for: intermediateSessionKey, using: SymmetricKey(data: transcriptHash)))
    func expand(_ info: Data) -> Data {
      let block = info + Data([RappCpaceConstants.firstExpandBlock])
      let code = HMAC<SHA512>.authenticationCode(
        for: block, using: SymmetricKey(data: pseudorandomKey))
      return Data(Data(code).prefix(RappCpaceConstants.expandedKeySize))
    }
    func tag(key: Data, domain: Data) -> Data {
      let code = HMAC<SHA512>.authenticationCode(
        for: cpaceLvCat([domain, transcriptHash]), using: SymmetricKey(data: key))
      return Data(Data(code).prefix(RappCpaceConstants.tagSize))
    }
    presharedKey = expand(RappCpaceConstants.pskInfo)
    initiatorTag = tag(
      key: expand(RappCpaceConstants.confirmAKeyInfo),
      domain: RappCpaceConstants.confirmATagDomain)
    responderTag = tag(
      key: expand(RappCpaceConstants.confirmBKeyInfo),
      domain: RappCpaceConstants.confirmBTagDomain)
  }
}
