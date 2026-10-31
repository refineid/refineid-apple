// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security

/// Canonical XML reconstruction and timestamp validation for ASiC-E verification.
extension AsicVerification {
  private static let sha256ByteCount = 32
  private static let sha384ByteCount = 48
  private static let sha512ByteCount = 64

  internal static func canonicalizeSignedInfo(parsed: ParsedSignature) -> String? {
    guard let c14nMethod = parsed.canonicalizationMethod,
      let sigMethod = parsed.signatureMethod
    else {
      return nil
    }

    var out = #"<ds:SignedInfo xmlns:ds="\#(XadesSignature.namespaceDsig)">"# + "\n"
    out +=
      #"<ds:CanonicalizationMethod Algorithm="\#(c14nMethod)"></ds:CanonicalizationMethod>"# + "\n"
    out += #"<ds:SignatureMethod Algorithm="\#(sigMethod)"></ds:SignatureMethod>"# + "\n"

    for ref in parsed.references {
      out += "<ds:Reference"
      if let identifier = ref.identifier {
        out += #" Id="\#(XadesSignature.escapeAttribute(identifier))""#
      }
      if let type = ref.type {
        out += #" Type="\#(XadesSignature.escapeAttribute(type))""#
      }
      out += #" URI="\#(XadesSignature.escapeAttribute(ref.uri))">"# + "\n"
      if !ref.transforms.isEmpty {
        out += "<ds:Transforms>\n"
        for transform in ref.transforms {
          out +=
            #"<ds:Transform Algorithm="\#(XadesSignature.escapeAttribute(transform))"></ds:Transform>"#
            + "\n"
        }
        out += "</ds:Transforms>\n"
      }
      out += #"<ds:DigestMethod Algorithm="\#(ref.digestMethod)"></ds:DigestMethod>"# + "\n"
      out += "<ds:DigestValue>\(ref.digestValue.base64EncodedString())</ds:DigestValue>\n"
      out += "</ds:Reference>\n"
    }

    out += "</ds:SignedInfo>"
    return out
  }

  /// Verifies the signature time-stamps and answers the earliest
  /// time among them.
  ///
  /// Each token must be authentic and imprint the canonicalised
  /// `ds:SignatureValue` element (EN 319 132-1 clause 5.3). Valid only
  /// when there is at least one and every one passes. Archive and
  /// data object time-stamps are not signature time-stamps
  /// (EN 319 132-1 clauses 5.5.2 and 5.2.8) and take no part.
  internal static func verifyTimestamps(
    parsed: ParsedSignature
  ) -> (valid: Bool, timestampedAt: Date?) {
    guard !parsed.signatureTimestampTokens.isEmpty else {
      return (false, nil)
    }

    var verifiedDates: [Date] = []

    for token in parsed.signatureTimestampTokens {
      guard let verified = try? TimestampTokenVerifier.verify(token),
        let contents = try? RfcTimestamp.contents(in: token),
        let binding = try? RfcTimestamp.binding(in: contents.tstInfo)
      else {
        continue
      }

      if matchesSignatureValue(parsed: parsed, expectedDigest: binding.digest) {
        verifiedDates.append(verified.generatedAt)
      }
    }

    let allValid =
      !verifiedDates.isEmpty && verifiedDates.count == parsed.signatureTimestampTokens.count
    return (allValid, verifiedDates.min())
  }

  private static func matchesSignatureValue(
    parsed: ParsedSignature,
    expectedDigest: Data
  ) -> Bool {
    let hashAlgorithm: String
    switch expectedDigest.count {
    case sha256ByteCount:
      hashAlgorithm = "sha256"
    case sha384ByteCount:
      hashAlgorithm = "sha384"
    case sha512ByteCount:
      hashAlgorithm = "sha512"
    default:
      hashAlgorithm = "sha384"
    }

    let candidates = signatureValueCandidates(parsed: parsed)
    for candidate in candidates {
      if let candDigest = digest(of: Data(candidate.utf8), algorithm: hashAlgorithm),
        candDigest == expectedDigest
      {
        return true
      }
    }
    return false
  }

  private static func signatureValueCandidates(parsed: ParsedSignature) -> [String] {
    var list: [String] = []
    let base64 = parsed.signatureValueBytes?.base64EncodedString() ?? ""
    let idAttr = parsed.signatureValueId.map { " Id=\"\($0)\"" } ?? ""

    list.append(
      #"<ds:SignatureValue xmlns:ds="\#(XadesSignature.namespaceDsig)"\#(idAttr)>\#(base64)</ds:SignatureValue>"#
    )
    list.append(
      #"<ds:SignatureValue xmlns:ds="\#(XadesSignature.namespaceDsig)">\#(base64)</ds:SignatureValue>"#
    )
    if let raw = parsed.signatureValueRawXml {
      list.append(raw)
      list.append(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return list
  }

  internal static func digest(of data: Data, algorithm: String) -> Data? {
    let lower = algorithm.lowercased()
    if lower.contains("sha384") {
      return Data(SHA384.hash(data: data))
    }
    if lower.contains("sha256") {
      return Data(SHA256.hash(data: data))
    }
    if lower.contains("sha512") {
      return Data(SHA512.hash(data: data))
    }
    return nil
  }

  internal static func resolveSecKeyAlgorithm(method: String) -> SecKeyAlgorithm? {
    if method.contains("ecdsa") {
      if method.contains("sha384") {
        return .ecdsaSignatureDigestX962SHA384
      }
      if method.contains("sha256") {
        return .ecdsaSignatureDigestX962SHA256
      }
      if method.contains("sha512") {
        return .ecdsaSignatureDigestX962SHA512
      }
    } else if method.contains("rsa") {
      if method.contains("sha384") {
        return .rsaSignatureDigestPKCS1v15SHA384
      }
      if method.contains("sha256") {
        return .rsaSignatureDigestPKCS1v15SHA256
      }
      if method.contains("sha512") {
        return .rsaSignatureDigestPKCS1v15SHA512
      }
    }
    return nil
  }

  internal static func resolveHashAlgorithmName(method: String) -> String? {
    if method.contains("sha384") {
      return "sha384"
    }
    if method.contains("sha256") {
      return "sha256"
    }
    if method.contains("sha512") {
      return "sha512"
    }
    return nil
  }
}
