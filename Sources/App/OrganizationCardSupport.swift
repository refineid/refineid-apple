// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Whether this build supports organization cards at all.
///
/// Set at build time by `FEATURE_ORGANIZATION_CARD`
/// (`Config/Features.xcconfig`): no configuration sets it right now,
/// so every build on every platform compiles without organization
/// cards until it is turned on there. The app and the token
/// extension derive their answer from the same compilation
/// condition, so the targets cannot disagree.
internal enum OrganizationCardSupport {
  internal static var isEnabled: Bool {
    #if FEATURE_ORGANIZATION_CARD
      true
    #else
      false
    #endif
  }
}
