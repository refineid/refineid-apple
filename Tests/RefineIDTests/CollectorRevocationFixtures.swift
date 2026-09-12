// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

@testable import RefineID

/// Generated certificate and CRL material for collector boundary tests.
internal enum CollectorRevocationFixtures {
  /// A direct issuer, two revoked leaves, and their authenticated status.
  internal struct Material: Sendable {
    /// The issuer certificate advertised by both leaves.
    internal let issuerCertificate: Data

    /// The revoked document-signing certificate.
    internal let documentSignerCertificate: Data

    /// The revoked timestamp-authority certificate.
    internal let timestampAuthorityCertificate: Data

    /// The issuer-signed CRL listing both leaf serials.
    internal let revocationList: Data

    /// A time inside every certificate and CRL validity interval.
    internal let currentTime: Date
  }

  /// Certificate fields that vary across generated fixtures.
  internal struct CertificateDescription {
    /// The certificate subject common name.
    internal let commonName: String

    /// The encoded direct issuer Name.
    internal let issuerName: Data

    /// The positive certificate serial.
    internal let serial: Data

    /// The subject private key whose public half is encoded.
    internal let publicKey: P256.Signing.PrivateKey

    /// The private key authenticating the TBSCertificate.
    internal let signer: P256.Signing.PrivateKey

    /// Whether BasicConstraints and KeyUsage authorize a CA.
    internal let certificateAuthority: Bool

    /// Whether extended key usage authorizes timestamp signing.
    internal let timestampAuthority: Bool
  }

  /// Errors confined to generated test material and injected I/O.
  internal enum Failure: Error {
    /// A checked-in test key could not be decoded.
    case invalidKeyEncoding

    /// Collection attempted an endpoint outside the fixture contract.
    case unexpectedIo
  }

  /// The AIA issuer location advertised by both generated leaves.
  internal static let issuerAddress = "https://ca.example/issuer.der"

  /// The distribution point advertised by both generated leaves.
  internal static let revocationListAddress = "https://ca.example/status.crl"

  /// Makes deterministic collector dependencies backed by one fixture.
  internal static func dependencies(
    for material: Material
  ) -> ValidationMaterialCollector.Dependencies {
    ValidationMaterialCollector.Dependencies(
      get: { address, allowingListSize in
        if address == Self.issuerAddress, !allowingListSize {
          return material.issuerCertificate
        }
        if address == Self.revocationListAddress, allowingListSize {
          return material.revocationList
        }
        throw Failure.unexpectedIo
      },
      post: { _, _, _ in throw Failure.unexpectedIo },
      now: { material.currentTime },
      random: { _ in throw Failure.unexpectedIo }
    )
  }
}
