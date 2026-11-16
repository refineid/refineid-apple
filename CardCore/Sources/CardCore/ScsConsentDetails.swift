// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// Holder-facing consent text for an SCS signature prompt (DVV SCS
/// specification v1.3 §2.1, §3.7).
///
/// Every prompt names the sanitized requesting `Origin` (or its
/// absence), the action, the certificate holder when readable, and the
/// SHA-256 fingerprint of the exact bytes being signed.
public enum ScsConsentDetails {
  /// Lowercase hexadecimal SHA-256 digest of `data`.
  public static func sha256Hex(of data: Data) -> String {
    SHA256.hash(data: data).map { byte in String(format: "%02x", byte) }.joined()
  }

  /// Localized multi-line consent body naming origin, action, optional
  /// signer, and SHA-256 fingerprint.
  public static func format(
    origin: String?,
    purpose: ScsSignPurpose,
    signerName: String?,
    sha256Hex: String,
    bundle: Bundle
  ) -> String {
    var lines = [
      originLine(origin: origin, bundle: bundle),
      actionLine(purpose: purpose, bundle: bundle),
    ]
    if let sanitizedSigner = ScsOriginPolicy.sanitizedSignerName(signerName) {
      lines.append(signerLine(purpose: purpose, signerName: sanitizedSigner, bundle: bundle))
    }
    lines.append(digestLine(sha256Hex: sha256Hex, bundle: bundle))
    return lines.joined(separator: "\n")
  }

  /// Localized confirmation button title matching the action (`Log in`
  /// for authentication, `Sign` for qualified signing).
  public static func confirmTitle(purpose: ScsSignPurpose, bundle: Bundle) -> String {
    switch purpose {
    case .authentication:
      String(localized: "Log in", bundle: bundle)

    case .qualified:
      String(localized: "Sign", bundle: bundle)
    }
  }

  private static func originLine(origin: String?, bundle: Bundle) -> String {
    if let sanitized = ScsOriginPolicy.sanitizedForDisplay(origin) {
      return String(localized: "Origin: \(sanitized)", bundle: bundle)
    }
    return String(
      localized: "Origin: (none - the request sent no Origin header)",
      bundle: bundle
    )
  }

  private static func actionLine(purpose: ScsSignPurpose, bundle: Bundle) -> String {
    switch purpose {
    case .authentication:
      String(localized: "Action: Log in", bundle: bundle)

    case .qualified:
      String(localized: "Action: Sign document", bundle: bundle)
    }
  }

  private static func signerLine(
    purpose: ScsSignPurpose,
    signerName: String,
    bundle: Bundle
  ) -> String {
    switch purpose {
    case .authentication:
      String(localized: "Logging in as: \(signerName)", bundle: bundle)

    case .qualified:
      String(localized: "Signing as: \(signerName)", bundle: bundle)
    }
  }

  private static func digestLine(sha256Hex: String, bundle: Bundle) -> String {
    String(localized: "Digest (SHA-256): \(sha256Hex)", bundle: bundle)
  }
}
