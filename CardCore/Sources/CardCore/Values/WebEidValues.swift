// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Named protocol, cryptographic, and IPC constants for the Web eID v2
/// browser-extension protocol.
public enum WebEidValues {
  /// Authentication token format identifier (Web eID architecture specification).
  public static let tokenFormat = "web-eid:1.0"

  /// SemVer reported to `web-eid.js` for protocol v2.x compatibility.
  public static let compatibleProtocolVersion = "2.6.0"

  /// Public release-URL prefix carried in `appVersion` of authentication tokens.
  public static let appVersionPrefix = "https://www.refineid.fi/releases/"

  /// Minimum character count for a 256-bit Base64 challenge nonce (`web-eid-app`).
  public static let minimumChallengeNonceLength = 44

  /// Maximum character count for a challenge nonce (`web-eid-app`).
  public static let maximumChallengeNonceLength = 128

  /// Maximum length of a `hashFunction` algorithm name string (`"SHA3-512"`).
  public static let maximumHashFunctionNameLength = 8

  /// Default user-interaction timeout in seconds (2 minutes, `web-eid.js`).
  public static let defaultUserInteractionTimeoutSeconds: TimeInterval = 120

  /// Minimum clamped bridge wait timeout in seconds.
  public static let minimumBridgeTimeoutSeconds: TimeInterval = 5

  /// Maximum clamped bridge wait timeout in seconds.
  public static let maximumBridgeTimeoutSeconds: TimeInterval = 300

  /// Age after which orphaned bridge files are swept from the App Group folder.
  public static let staleBridgeFileAgeSeconds: TimeInterval = 300

  /// Milliseconds per second for converting JS `userInteractionTimeout`.
  public static let millisecondsPerSecond: TimeInterval = 1_000

  /// Required URL scheme for Web eID relying-party origins.
  public static let requiredOriginScheme = "https"

  /// Shared App Group identifier linking RefineID and its Safari Web Extension.
  public static let appGroupIdentifier = "group.fi.refineid.RefineID"

  /// Subdirectory name inside the App Group container for Web eID IPC files.
  public static let bridgeDirectoryName = "WebEidBridge"

  /// Darwin notification posted when a new Web eID request is written.
  public static let requestNotification = "fi.refineid.webeid.request"

  /// Darwin notification posted when a Web eID response is written.
  public static let responseNotification = "fi.refineid.webeid.response"

  /// POSIX mode `0700` for the private Web eID IPC directory.
  public static let bridgeDirectoryPermissions = 0o700

  /// POSIX mode `0600` for Web eID IPC request/response files.
  public static let bridgeFilePermissions = 0o600

  /// JWS algorithm identifier for ECDSA P-256 with SHA-256.
  public static let jwsEs256 = "ES256"

  /// JWS algorithm identifier for ECDSA P-384 with SHA-384.
  public static let jwsEs384 = "ES384"

  /// JWS algorithm identifier for RSASSA-PKCS1-v1_5 with SHA-256.
  public static let jwsRs256 = "RS256"

  /// Web eID `cryptoAlgorithm` identifier for elliptic-curve keys.
  public static let cryptoAlgorithmEcc = "ECC"

  /// Web eID `cryptoAlgorithm` identifier for RSA keys.
  public static let cryptoAlgorithmRsa = "RSA"

  /// Web eID `paddingScheme` identifier for unpadded ECDSA signatures.
  public static let paddingSchemeNone = "NONE"

  /// Web eID `paddingScheme` identifier for RSASSA-PKCS1-v1_5 signatures.
  public static let paddingSchemePkcs1 = "PKCS1.5"
}
