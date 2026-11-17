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

  // The gate scripts are host tooling, and Process does not exist on iOS, so
  // the plan checks compile for macOS only.
  #if os(macOS)
    /// Asks a gate script what it will do and returns the answer.
    ///
    /// Both plan modes run no step, so this checks a gate's resolved plan
    /// rather than the text of the script that builds it.
    private static func gatePlan(_ script: String, _ arguments: String...) throws -> String {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/bin/bash")
      process.arguments = [script] + arguments
      process.currentDirectoryURL = root
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = pipe
      try process.run()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let answer = try #require(String(bytes: data, encoding: .utf8))
      process.waitUntilExit()
      #expect(
        process.terminationStatus == 0,
        "\(script) \(arguments.joined(separator: " ")) exited \(process.terminationStatus):\n\(answer)"
      )
      return answer
    }
  #endif

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

  @Test("The artifact is named by the release tag it was cut from")
  internal func artifactIsNamedByItsTag() throws {
    let source = try Self.builderSource()
    #expect(source.contains("\"\\(appName)-\\(tag).dmg\""))
    #expect(source.contains("MARKETING_VERSION"))
    #expect(source.contains("--tag is required"))
    // The time-stamped name identified the run, not the source: two runs on one
    // day were told apart only by when they happened.
    #expect(!source.contains("utcBuildTimeStamp"))
    #expect(!source.contains("HHmm"))
    let runbook = try Self.text("Documentation/release-runbook.md")
    #expect(runbook.contains("RefineID-v<MARKETING_VERSION>-<CURRENT_PROJECT_VERSION>-dev.dmg"))
  }

  @Test("The build is the annotated tag that points at HEAD")
  internal func buildRequiresTheAnnotatedTagAtHead() throws {
    let source = try Self.builderSource()
    #expect(source.contains(#""tag", "--points-at", "HEAD""#))
    #expect(source.contains(#""cat-file", "-t""#))
    #expect(source.contains("refs/tags/"))
    #expect(source.contains("uncommitted changes or untracked files"))
    // Untracked files are part of that check: a source file the commit does not
    // contain would be compiled into an image its tag cannot reproduce.
    #expect(!source.contains("--untracked-files=no"))
    #expect(source.contains("does not name this build"))
    #expect(source.contains("not an annotated tag"))
    // The identity is stamped into the app, so the artifact says where it came from.
    #expect(source.contains("REFINEID_BUILD_SOURCE="))
    #expect(source.contains("identity.buildSource"))
    // A tag moves no file, so the cached app is keyed by the source as well.
    #expect(source.contains("recordedBuildSource(derivedData:"))
    #expect(source.contains("build-source-stamp"))
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

  @Test("The signed bundles carry the entitlements the app needs")
  internal func signingCarriesEntitlements() throws {
    let source = try Self.builderSource()
    // Signing a bundle re-signs its main executable, so the entitlements must
    // be passed to the bundle as well as to the executable.
    #expect(
      source.contains("codesignItem(app, identity: signingIdentity, entitlements: appEntitlements)")
    )
    #expect(
      source.contains(
        "codesignItem(tokenAppEx, identity: signingIdentity, entitlements: tokenEntitlements)"
      ))
    // A signature that verifies can still carry no entitlements.
    #expect(source.contains("com.apple.security.app-sandbox"))
    #expect(source.contains("com.apple.security.smartcard"))
    #expect(source.contains("is signed without"))
  }

  @Test("The disk image is signed, then notarized, then assessed")
  internal func diskImageIsSignedBeforeNotarization() throws {
    let source = try Self.builderSource()
    let signed = try #require(source.range(of: "signDmg(dmg: dmg"))
    let notarized = try #require(source.range(of: "notarizeDmg(dmg: dmg"))
    let assessed = try #require(source.range(of: "assessDmg(dmg: dmg"))
    // Stapling writes the ticket into the image, so a signature added later
    // would replace the signature and discard the ticket.
    #expect(signed.lowerBound < notarized.lowerBound)
    #expect(notarized.lowerBound < assessed.lowerBound)
    // Gatekeeper assesses the image itself, so the signature on the app inside
    // is not enough, and a signature from another team would still verify.
    #expect(source.contains(#""TeamIdentifier=\(teamId)""#))
    #expect(source.contains("context:primary-signature"))
    let runbook = try Self.text("Documentation/release-runbook.md")
    #expect(runbook.contains("signs the disk image itself"))
  }

  @Test("A successful run leaves only the newest artifact")
  internal func supersededArtifactsAreRemoved() throws {
    let source = try Self.builderSource()
    #expect(source.contains("pruneSupersededArtifacts(in: outputDirectory, keeping: dmg)"))
    let checksum = try #require(source.range(of: "writeChecksumFile(for: dmg)"))
    let pruned = try #require(source.range(of: "pruneSupersededArtifacts(in:"))
    // Removal follows the checksum: a run that stops earlier must not delete
    // the artifact it has not replaced yet.
    #expect(checksum.lowerBound < pruned.lowerBound)
    #expect(source.contains("removed superseded"))
    let runbook = try Self.text("Documentation/release-runbook.md")
    #expect(runbook.contains("older artifacts"))
  }

  #if os(macOS)
    @Test("The lint gate typechecks the builder and its tests")
    internal func gateCoversTheBuilder() throws {
      let lint = try Self.gatePlan("Scripts/lint.sh", "list")
      #expect(lint.contains("typecheck \(Self.builderPath)"))
      #expect(lint.contains("typecheck \(Self.builderTestsPath)"))
      // Both files stay outside the swift-format run: the formatter joins a
      // license comment onto the line above it, which would turn the shebang
      // into an interpreter line carrying arguments.
      #expect(!lint.contains("format \(Self.builderPath)"))
      #expect(!lint.contains("format \(Self.builderTestsPath)"))
    }

    @Test("The PR gate runs the builder command-line tests")
    internal func prGateRunsTheBuilderTests() throws {
      let gate = try Self.gatePlan("Scripts/test.sh", "plan", "pr")
      #expect(gate.contains("swift \(Self.builderTestsPath)"))
      #expect(gate.contains("direct-download DMG builder command-line tests"))
    }
  #endif

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
