// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if FEATURE_SCS && os(macOS)
  /// Connection cap and deadline bounds for `ScsServer`.
  internal struct ScsServerLimits: Sendable {
    private static let defaultMaximumConnections = 8
    private static let defaultReadTimeoutSeconds: Double = 15
    private static let defaultSignTimeoutSeconds: Double = 120

    internal static let standard = Self(
      maximumConnections: defaultMaximumConnections,
      readTimeoutSeconds: defaultReadTimeoutSeconds,
      signTimeoutSeconds: defaultSignTimeoutSeconds
    )

    internal let maximumConnections: Int
    internal let readTimeoutSeconds: Double
    internal let signTimeoutSeconds: Double
  }
#endif
