// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// Accesses issuing CA certificates for card leaf certificates.
///
/// Looks up intermediate or root CA certificates from the trust roots
/// cache to complete certificate chains for verification and reporting.
public enum IssuerCertificate {
  /// Returns the matching intermediate in DER form from the trust roots cache.
  public static func der(matching leafDER: Data) -> Data? {
    TrustRootsCache.shared.der(matching: leafDER)
  }
}
