// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// The shipped list-signing certificates.
@Suite
internal struct EuListOfTheListsSignersTests {
  /// Every shipped DER loads, parses as a certificate and hashes to the
  /// fingerprint the Official Journal notice lists.
  @Test
  internal func theShippedCertificatesMatchTheNotice() throws {
    let certificates = EuListOfTheListsSigners.certificates
    try #require(certificates.count == EuListOfTheListsSigners.count)
    for (certificate, fingerprint) in zip(certificates, EuListOfTheListsSigners.fingerprints) {
      #expect(EuListOfTheListsSigners.fingerprint(of: certificate) == fingerprint)
      #expect(CertificateFacts(der: certificate) != nil)
    }
    #expect(Set(certificates).count == EuListOfTheListsSigners.count)
  }
}
