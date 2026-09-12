// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// swift-tools-version: 6.3

// PKCS11Bridge: a PKCS#11 v2.40 module over CryptoTokenKit and
// Security.framework. It never touches the card: identities come from
// SecItemCopyMatching and signatures from SecKeyCreateSignature, so the
// system token daemon and the RefineID token extension do all card work.
// Consumers: Java SunPKCS11, Firefox/NSS, OpenSSH.
import PackageDescription

private let warningsAsErrors: [SwiftSetting] = [
  .treatAllWarnings(as: .error)
]

private let package = Package(
  name: "PKCS11Bridge",
  platforms: [
    .macOS("26.0")
  ],
  products: [
    .library(name: "PKCS11Bridge", type: .dynamic, targets: ["PKCS11Bridge"])
  ],
  targets: [
    // The PKCS#11 C ABI: type/constant subset, all 68 entry-point
    // prototypes, the exported function list, and stubs for the
    // entry points the bridge does not implement.
    .target(
      name: "CCryptoki",
      cSettings: [
        .unsafeFlags(["-Werror"])
      ]),
    // The implemented entry points, exported with C names via @_cdecl.
    .target(
      name: "PKCS11Bridge",
      dependencies: ["CCryptoki"],
      swiftSettings: warningsAsErrors),
    .testTarget(
      name: "PKCS11BridgeTests",
      dependencies: ["PKCS11Bridge", "CCryptoki"],
      swiftSettings: warningsAsErrors),
  ]
)
