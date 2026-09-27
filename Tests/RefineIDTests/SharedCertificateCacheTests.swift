// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)
  import Testing

  /// Serializes suites that register and reset the same test certificate store.
  @Suite("Shared certificate cache", .serialized)
  internal enum SharedCertificateCacheTests {
    // The nested suites share TestCredentialEnvironment's CA persistence state.
  }
#endif
