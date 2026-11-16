// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@Suite("macOS notarized DMG builder")
internal struct MacosNotarizedDmgBuilderTests {
  // MARK: Static Computed Properties

  private static var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private static var builderPath: String {
    "Scripts/macos-notarized-dmg-builder.swift"
  }

  private static var builderTestsPath: String {
    "Scripts/TestMacosNotarizedDmgBuilder.swift"
  }

  // MARK: Static Functions

  private static func text(_ path: String) throws -> String {
    try String(contentsOf: root.appending(path: path), encoding: .utf8)
  }

  private static func builderSource() throws -> String {
    try text(builderPath)
  }

  // MARK: Functions

  @Test("Notarization credentials are the App Store Connect API key")
  internal func notarizationUsesAppStoreConnectKey() throws {
    let source = try Self.builderSource()
    #expect(source.contains("App Store Connect API key (.p8) that already signs the app"))
    #expect(source.contains("--key-id <key-id>"))
    #expect(source.contains("--issuer <issuer-id>"))
    // The Apple Account app-specific password flow and the Apple ID it needs
    // are not this project's credentials model.
    #expect(!source.contains("app-specific password"))
    #expect(!source.contains("--apple-id"))
    #expect(!source.contains("account.apple.com"))
    #expect(!source.contains("petri.koistinen@"))
  }

  @Test("The artifact name carries the marketing version and the UTC build time")
  internal func artifactNameIsVersioned() throws {
    let source = try Self.builderSource()
    #expect(source.contains(#""\(appName)-v\(marketingVersion()).\(utcBuildTimeStamp()).dmg""#))
    #expect(source.contains("MARKETING_VERSION"))
    #expect(source.contains("formatter.timeZone = TimeZone(secondsFromGMT: 0)"))
    #expect(source.contains(#"formatter.dateFormat = "HHmm""#))
  }

  @Test("The signing team comes from the committed configuration")
  internal func signingTeamComesFromConfiguration() throws {
    let source = try Self.builderSource()
    #expect(source.contains("DEVELOPMENT_TEAM"))
    #expect(source.contains("developmentTeam()"))
    // The team is public and committed, so the builder must not keep its own
    // copy of it that can drift from the checkout.
    #expect(!source.contains(#"var teamId = "4ZJC3SFJR2""#))
    let version = try Self.text("Version.xcconfig")
    #expect(version.contains("DEVELOPMENT_TEAM ="))
    let runbook = try Self.text("Documentation/release-runbook.md")
    #expect(runbook.contains("`DEVELOPMENT_TEAM` in `Version.xcconfig`"))
  }

  @Test("A published artifact is not replaced without overwrite")
  internal func publishedArtifactIsNotReplacedSilently() throws {
    let source = try Self.builderSource()
    #expect(source.contains("already exists; pass --overwrite to replace it"))
    #expect(source.contains(#"case "--overwrite":"#))
  }

  @Test("A cached app is reused only against the recorded build stamp")
  internal func rebuildDecisionUsesRecordedStamp() throws {
    let source = try Self.builderSource()
    #expect(source.contains(#"private let buildStampFileName = "build-input-stamp""#))
    #expect(source.contains("recordedBuildInputDate(derivedData:"))
    #expect(source.contains(#"case "--force-rebuild":"#))
    #expect(source.contains("newest > recorded"))
  }

  @Test("The DMG installs by dragging the app onto Applications")
  internal func dmgCarriesTheApplicationsLink() throws {
    let source = try Self.builderSource()
    #expect(source.contains(#"stagingDirectory.appendingPathComponent("Applications")"#))
    #expect(
      source.contains(
        #"withDestinationURL: URL(fileURLWithPath: "/Applications", isDirectory: true)"#
      ))
  }

  @Test("The lint gate typechecks the builder and its tests")
  internal func gateCoversTheBuilder() throws {
    let lint = try Self.text("Scripts/lint.sh")
    #expect(
      lint.contains(
        #"typecheck "macOS notarized DMG builder" Scripts/macos-notarized-dmg-builder.swift"#
      ))
    #expect(
      lint.contains(
        #"typecheck "macOS notarized DMG builder tests" Scripts/TestMacosNotarizedDmgBuilder.swift"#
      ))
    // Both files stay outside the swift-format run: the formatter joins a
    // license comment onto the line above it, which would turn the shebang
    // into an interpreter line carrying arguments.
    let formatPaths = try #require(
      lint.components(separatedBy: "format_paths=(").last?
        .components(separatedBy: ")").first)
    #expect(!formatPaths.contains(Self.builderPath))
    #expect(!formatPaths.contains(Self.builderTestsPath))
  }

  @Test("The PR gate runs the builder command-line tests")
  internal func prGateRunsTheBuilderTests() throws {
    let gate = try Self.text("Scripts/test.sh")
    #expect(gate.contains("swift \(Self.builderTestsPath)"))
    #expect(gate.contains("direct-download DMG builder command-line tests"))
  }

  @Test("The runbook names both release CLIs and the artifact scope")
  internal func runbookNamesBothEntryPoints() throws {
    let runbook = try Self.text("Documentation/release-runbook.md")
    #expect(runbook.contains(Self.builderPath))
    #expect(runbook.contains("is the public release CLI for the"))
    #expect(runbook.contains("direct-download DMG only"))
    #expect(runbook.contains("The build is arm64 only."))
    #expect(runbook.contains("`Applications` link"))
    #expect(runbook.contains("build-input-stamp"))
    #expect(runbook.contains("--team-id"))
  }
}
