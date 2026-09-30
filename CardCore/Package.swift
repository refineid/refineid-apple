// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// swift-tools-version: 6.3

// CardCore: the refined FINEID protocol model and card operations.
// Platform-independent Swift with no UI and no CryptoTokenKit; the app and
// the token extension both consume it.
import PackageDescription

// Xcode injects -suppress-warnings on local package products, which
// conflicts with -warnings-as-errors. App targets already treat warnings
// as errors. Tests are command-line only, so they keep the flag.
private let warningsAsErrors: [SwiftSetting] = [
  .treatAllWarnings(as: .error)
]

private let package = Package(
  name: "CardCore",
  platforms: [
    // The app floor is iOS 26 and macOS 26; CardCore matches it.
    .iOS("26.0"),
    .macOS("26.0"),
  ],
  products: [
    .library(name: "CardCore", targets: ["CardCore"])
  ],
  targets: [
    // The RAPP protocol engine in Swift: deterministic CBOR, the envelope
    // schema, the Noise handshakes and transport channel, the formal state
    // model, the storage codecs, and the two operation engines. It implements
    // the vendored specification and is replayed against the vendored
    // conformance corpus and the vectors generated from the reference engine.
    .target(
      name: "RappEngine",
      path: "Sources/RappEngine"),
    // Tests live in the Xcode project's Tests/CardCoreTests bundle target
    // so one scheme runs them locally and in Xcode Cloud.
    // They exercise the public API only.
    .target(
      name: "CardCore",
      dependencies: [
        "ObjCExceptionGuard",
        "PcscCardReset",
        "RappEngine",
      ],
      swiftSettings: [
        .define("REFINEID_STREAM_TRANSPORT")
      ],
      linkerSettings: [
        .linkedFramework("Security")
      ]),
    // The engine's conformance replays run here rather than in the Xcode
    // project's test bundle, so they also run from the command line.
    .testTarget(
      name: "RappEngineTests",
      dependencies: ["RappEngine"],
      path: "Tests/RappEngineTests",
      swiftSettings: warningsAsErrors),
    // Objective-C, because catching an Objective-C exception is a
    // thing only Objective-C can do.
    .target(name: "ObjCExceptionGuard"),
    // C, because the PCSC module is marked unimportable from Swift
    // while its C interface remains fully supported.
    .target(
      name: "PcscCardReset",
      linkerSettings: [
        .linkedFramework("PCSC", .when(platforms: [.macOS]))
      ]),
  ],
  swiftLanguageModes: [.v6]
)
