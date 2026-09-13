// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// Accesses issuing certificates for card leaf certificates.
///
/// Rather than bundling static issuing CA certificates into software binaries,
/// certificates are read from the card once, verified, and persistently stored.
public enum BundledIssuerCertificate {
  /// Returns the matching intermediate in DER form from the trust roots cache.
  public static func der(
    matching leafDER: Data,
    in bundle: Bundle = .main
  ) -> Data? {
    _ = bundle
    return TrustRootsCache.shared.der(matching: leafDER)
  }
}
