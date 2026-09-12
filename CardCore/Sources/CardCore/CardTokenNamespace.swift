// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The CryptoTokenKit namespace owned by RefineID.
///
/// The driver class identifier is fixed by the extension manifest. Keeping
/// its token-ID spelling here gives the app and extension one source of truth
/// for registration, status, and revocation.
public enum CardTokenNamespace {
  /// The token driver's class identifier.
  public static let driverClassIdentifier = "fi.refineid.ReFineID.token"

  /// Driver class identifiers shipped by older RefineID builds.
  ///
  /// They no longer create tokens, but a persistent Safari registration
  /// can outlive the build that created it. Destructive RefineID cleanup
  /// owns these registrations too; it must not mistake "old" for
  /// "somebody else's".
  private static let legacyDriverClassIdentifiers = [
    "fi.refineid.ReFineID.ctk"
  ]

  /// CryptoTokenKit separates the class and instance identifiers with this.
  private static let identifierSeparator = ":"

  /// Prefix shared by every RefineID smart-card token identifier.
  public static let tokenPrefix = driverClassIdentifier + identifierSeparator

  /// Every token prefix ever issued by RefineID.
  private static let ownedTokenPrefixes =
    ([driverClassIdentifier] + legacyDriverClassIdentifiers)
    .map { $0 + identifierSeparator }

  /// The full CryptoTokenKit token identifier for one physical card.
  public static func tokenIdentifier(for instance: CardInstanceIdentifier) -> String {
    tokenPrefix + instance.value
  }

  /// Whether a full token identifier belongs to this driver.
  public static func owns(tokenIdentifier: String) -> Bool {
    ownedTokenPrefixes.contains { tokenIdentifier.hasPrefix($0) }
  }

  /// Whether a full token identifier names a remote-card identity
  /// configured under a card driver class.
  ///
  /// The remote card publishes under `PersistentTokenIdentity.classID`;
  /// under a card class, an instance carrying its name is what a build
  /// before the driver split configured there. The system lists it as
  /// a present card for as long as it stays, so anything asking "is a
  /// card available?" has to refuse it by name.
  public static func isDisplacedRemoteCardToken(tokenIdentifier: String) -> Bool {
    ownedTokenPrefixes.contains { prefix in
      tokenIdentifier.hasPrefix(prefix + PersistentTokenIdentity.instancePrefix)
    }
  }
}
