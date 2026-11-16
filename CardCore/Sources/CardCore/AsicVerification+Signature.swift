// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Cryptographic signature verification over canonical XAdES `ds:SignedInfo` elements.
extension AsicVerification {
  /// Verifies `parsed.signatureValueBytes` over canonical `ds:SignedInfo` under `signerCertificate`.
  internal static func verifyCryptographicSignature(
    parsed: ParsedSignature,
    signerCertificate: Data
  ) -> Bool {
    guard
      !parsed.hasStructuralError,
      let signedInfo = parsed.signedInfoElement,
      let canonicalization = parsed.signedInfoCanonicalization,
      let method = parsed.parsedSignatureMethod,
      let signatureBytes = parsed.signatureValueBytes,
      let canonicalSignedInfo = XmlCanonicalizer.canonicalize(
        signedInfo, method: canonicalization, omitting: nil)
    else {
      return false
    }
    return method.verifies(
      signatureBytes, over: canonicalSignedInfo, certificate: signerCertificate)
  }
}
