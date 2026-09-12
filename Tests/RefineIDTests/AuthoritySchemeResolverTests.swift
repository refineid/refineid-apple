// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Testing

@testable import RefineID

/// Direct checks for authority-address syntax before any network probe.
@Suite
internal struct AuthoritySchemeResolverTests {
  /// Exact HTTP and HTTPS URLs with a host are accepted, including an
  /// uppercase scheme as URL syntax permits.
  @Test
  internal func httpFamilyAddressesAreUsable() {
    #expect(AuthoritySchemeResolver.isUsable("http://timestamp.example"))
    #expect(AuthoritySchemeResolver.isUsable("HTTPS://timestamp.example/path"))
  }

  /// Scheme lookalikes, unrelated schemes, and missing hosts are not
  /// addresses the timestamp client may use.
  @Test
  internal func otherAddressShapesAreNotUsable() {
    for address in [
      "timestamp.example",
      "httpish://timestamp.example",
      "file:///tmp/timestamp",
      "https:/missing-host",
    ] {
      #expect(!AuthoritySchemeResolver.isUsable(address))
    }
  }
}
