// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Security

@testable import RefineID

/// Generated, hermetic signer keys and certificates for direct tests.
internal enum SignerCertificateFixtures {
  /// Signature profiles a generated signer can carry.
  internal enum Profile {
    /// ECDSA on P-256.
    case ecdsaSha256

    /// ECDSA on P-521.
    case ecdsaSha512

    /// 2048-bit RSA.
    case rsaSha256

    /// The generated signer's key family.
    internal var keyKind: KeyKind {
      switch self {
      case .ecdsaSha256:
        return .ecdsaP256

      case .ecdsaSha512:
        return .ecdsaP521

      case .rsaSha256:
        return .rsa
      }
    }
  }

  /// Key families the factory can generate.
  internal enum KeyKind {
    /// P-256 ECDSA.
    case ecdsaP256

    /// P-521 ECDSA.
    case ecdsaP521

    /// 2048-bit RSA.
    case rsa
  }

  /// Controlled X.509 profiles for signer-policy tests.
  internal enum CertificateProfile: Equatable {
    /// No BasicConstraints extension, which denotes an end entity.
    case basicConstraintsAbsent

    /// An explicit CA assertion.
    case certificateAuthority

    /// Estonia's current integer-only end-entity BasicConstraints shape.
    case endEntityPathLength

    /// A certificate that ceased to be valid before the signed issue time.
    case expiredBeforeIssue

    /// No KeyUsage extension, so X.509 imposes no usage restriction.
    case keyUsageAbsent

    /// A present KeyUsage that permits encryption but not signatures.
    case nonSigningKeyUsage

    /// Signing KeyUsage and end-entity BasicConstraints.
    case valid
  }

  /// Controlled SubjectPublicKeyInfo encodings for RSA import tests.
  internal enum SubjectPublicKeyProfile: Equatable {
    /// rsaEncryption with the required NULL parameters.
    case rsaEncryption

    /// id-RSASSA-PSS with absent parameters.
    case rsaPssAbsentParameters

    /// id-RSASSA-PSS with explicitly empty parameters.
    case rsaPssEmptyParameters

    /// id-RSASSA-PSS with an incompatible INTEGER parameter.
    case rsaPssIntegerParameter

    /// id-RSASSA-PSS with NULL parameters.
    case rsaPssNullParameters

    /// The recognized algorithm but a BIT STRING with nonzero unused bits.
    case rsaPssUnusedBits
  }

  /// One generated private key and its matching X.509 certificate.
  internal struct Signer {
    internal let certificate: Data
    internal let key: SecKey
  }

  /// Failures constructing test-only cryptographic material.
  internal enum Failure: Error {
    /// Security could not create or export a key.
    case keyCreation

    /// Security could not create a signature.
    case signatureCreation
  }
}
