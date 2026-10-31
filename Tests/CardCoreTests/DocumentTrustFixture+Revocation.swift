// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation

  @testable import CardCore

  /// CRLs over the fixture hierarchy.
  extension DocumentTrustFixture {
    /// A CRL by the issuing CA, listing the signer when `revoking`.
    internal func revocationList(revoking: Bool) throws -> Data {
      var options = CertificateRevocationListFixtures.Options.standard
      options.listsTargetSerial = revoking
      options.revokedSerial = signerSerial
      return try CertificateRevocationListFixtures.crl(
        issuerKey: issuingKey, kind: kind, options: options
      )
    }

    /// A CRL by the root, listing the issuing CA when `revoking`.
    internal func rootRevocationList(revoking: Bool) throws -> Data {
      var options = CertificateRevocationListFixtures.Options.standard
      options.crlIssuerCommonName = Self.rootName
      options.listsTargetSerial = revoking
      options.revokedSerial = Self.issuingSerial
      return try CertificateRevocationListFixtures.crl(
        issuerKey: rootKey, kind: kind, options: options
      )
    }
  }

#endif
