// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Version facts read from the built product itself, so the window can never
/// claim a version that is not actually bundled.
internal struct BundledVersions {
  /// Bundle identifier of the extension that actually mints tokens.
  ///
  /// Two CryptoTokenKit extensions are embedded - the minting half and
  /// the discovery half that only declares an AID - so "the driver" has
  /// to be named rather than taken as whichever `.appex` the file system
  /// happens to list first. Keep in sync with the token extension
  /// target's PRODUCT_BUNDLE_IDENTIFIER.
  private static let driverBundleIdentifier = "fi.refineid.ReFineID.token"

  /// The file extension every embedded app extension carries.
  private static let extensionSuffix = "appex"

  /// Application version as "26.7.22 (124)", or nil when unreadable.
  internal let application: String?

  /// Where a development install was built from, as branch@commit, or
  /// nil for a clean main checkout and every store build.
  internal let source: String?

  /// The version followed by the source when there is one.
  internal var applicationWithSource: String? {
    guard let application else { return nil }
    guard let source else { return application }
    return application + " " + source
  }

  /// Version of the embedded CryptoTokenKit extension that mints tokens.
  ///
  /// Nil when that bundle cannot be located or read; the UI must then say
  /// so instead of guessing.
  internal let driver: String?

  /// Reads both versions from the given bundle (the main bundle in
  /// production).
  internal static func read(from bundle: Bundle) -> Self {
    Self(
      application: displayVersion(of: bundle),
      source: buildSource(of: bundle),
      driver: driverVersion(in: bundle)
    )
  }

  private static func buildSource(of bundle: Bundle) -> String? {
    let value = bundle.object(forInfoDictionaryKey: "RefineIDBuildSource") as? String
    return value.flatMap { $0.isEmpty ? nil : $0 }
  }

  private static func displayVersion(of bundle: Bundle) -> String? {
    guard
      let version = bundle.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
      ) as? String,
      let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    else {
      return nil
    }
    return "\(version) (\(build))"
  }

  /// The minting extension's version, found by identifier.
  ///
  /// Directory order is not an answer here: both embedded extensions end
  /// in `.appex`, so taking the first would report whichever one the file
  /// system listed - and would quietly report the wrong one the moment
  /// the two versions differ.
  private static func driverVersion(in bundle: Bundle) -> String? {
    guard
      let plugIns = bundle.builtInPlugInsURL,
      let contents = try? FileManager.default.contentsOfDirectory(
        at: plugIns,
        includingPropertiesForKeys: nil
      )
    else {
      return nil
    }
    let embedded = contents.filter { $0.pathExtension == Self.extensionSuffix }
    let minting = embedded.lazy
      .compactMap(Bundle.init(url:))
      .first { $0.bundleIdentifier == Self.driverBundleIdentifier }
    return minting.flatMap(displayVersion(of:))
  }
}
