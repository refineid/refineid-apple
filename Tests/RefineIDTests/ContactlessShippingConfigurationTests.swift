// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

/// The contactless gate holds end to end: exclusive files are
/// defined away, and the shipping macOS binary carries no
/// contactless user text.
@Suite("Contactless shipping configuration")
internal struct ContactlessShippingConfigurationTests {
  // MARK: Static Properties

  /// User text that lives only in contactless-exclusive code.
  private static let contactlessLiterals = [
    "Trying the CAN in memory.",
    "Put the card in the reader's card slot.",
    "Take the card off the reader.",
    "Put the card back.",
  ]

  // MARK: Static Computed Properties

  private static var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  // MARK: Static Functions

  /// The built RefineID app binaries beside the running test host:
  /// the executable, plus the debug dylib that carries app code in
  /// Debug builds.
  private static func shippedAppBinaries() -> [URL] {
    var url = URL(
      fileURLWithPath: ProcessInfo.processInfo.arguments[0])
    url.deleteLastPathComponent()
    url.deleteLastPathComponent()
    url.deleteLastPathComponent()
    url.deleteLastPathComponent()
    let folder = url.appending(path: "RefineID.app/Contents/MacOS")
    return ["RefineID", "RefineID.debug.dylib"]
      .map { name in folder.appending(path: name) }
      .filter { candidate in
        FileManager.default.fileExists(atPath: candidate.path)
      }
  }

  // MARK: Functions

  @Test("Contactless-exclusive files are defined away without the flag")
  internal func exclusiveFilesAreGated() throws {
    // The offer core, the credential store primitives, and the ask
    // write-side stay: the credentials UI, diagnostics, revocation
    // cleanup, the mocks, and the organization-card flow use them too.
    for (path, gate) in [
      (
        "Sources/App/SealedCardSection.swift",
        "#if os(macOS) && FEATURE_CONTACTLESS"
      ),
      (
        "Sources/App/StatusView+CardAsk.swift",
        "#if os(macOS) && FEATURE_CONTACTLESS"
      ),
      (
        "CardCore/Sources/CardCore/CardCredentialStore+Candidates.swift",
        "#if !os(macOS)"
      ),
    ] {
      let text = try String(
        contentsOf: Self.root.appending(path: path), encoding: .utf8)
      #expect(text.contains(gate), "\(path) is not gated")
    }
  }

  #if !FEATURE_CONTACTLESS
    @Test("The built app binary carries no contactless user text")
    internal func builtBinaryCarriesNoContactlessText() throws {
      let binaries = Self.shippedAppBinaries()
      try #require(!binaries.isEmpty)
      for binary in binaries {
        // Latin-1 maps every byte, so ASCII literals survive decoding.
        let text =
          String(
            bytes: try Data(contentsOf: binary), encoding: .isoLatin1) ?? ""
        for literal in Self.contactlessLiterals {
          #expect(
            !text.contains(literal),
            "\(literal) is present in \(binary.lastPathComponent)")
        }
      }
    }
  #endif
}
