// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Stable coordinates shared by the hosting app and persistent token driver.
public enum PersistentTokenIdentity {
  /// The CryptoTokenKit class identifier both processes configure under.
  public static let classID = "fi.refineid.ReFineID.rapp-token"

  /// CryptoTokenKit separates the class and instance identifiers with this.
  private static let identifierSeparator = ":"

  /// Prefix shared by every published remote-card token identifier.
  public static let tokenPrefix = classID + identifierSeparator

  /// Instance-identifier prefix of every published remote-card identity.
  public static let instancePrefix = "refineid-rapp-card-"

  /// Keychain object ID of the published authentication certificate.
  public static let certificateObjectID = "authentication-certificate"

  /// Keychain object ID of the published authentication key.
  public static let keyObjectID = "authentication-certificate"

  /// Whether a full token identifier belongs to the remote-card driver.
  public static func owns(tokenIdentifier: String) -> Bool {
    tokenIdentifier.hasPrefix(tokenPrefix)
  }
}
