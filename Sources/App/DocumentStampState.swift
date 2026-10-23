// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation

  /// One visible statement and the exact certificate that states it.
  internal struct DocumentStampState {
    internal let statement: StampRenderer.Statement
    internal let signerCertificate: Data
  }

#endif
