// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Whether a signer reached a certificate-issuing anchor.
public enum ChainStatus: Sendable, Equatable {
  /// The signer is fit to sign and has this validated path, signer
  /// first and anchor last.
  case anchored(path: [Data])

  /// No anchored path, or a signer unfit to sign; a carried
  /// certificate that directly issued the signer, when one did.
  case unanchored(directIssuer: Data?)

  /// The certificate that issued the signer.
  public var issuerCertificate: Data? {
    switch self {
    case .anchored(let path):
      path.count > 1 ? path[1] : nil

    case .unanchored(let directIssuer):
      directIssuer
    }
  }

  /// Whether the signer is anchored.
  public var isAnchored: Bool {
    guard case .anchored = self else { return false }
    return true
  }
}
