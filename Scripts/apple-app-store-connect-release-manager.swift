#!/usr/bin/env swift
// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
//
// Drive the complete Apple release lifecycle in the language this project
// is written in and with no shell release entry points.
//
// Local commands archive, inspect, export, and optionally upload a candidate.
// The remaining web-UI steps are JSON-over-HTTP calls, and doing them by hand
// leaves no record of what was done. This composes all of them into named
// commands. CryptoKit signs the ES256 token from the
// .p8 (which is a P-256 key), URLSession makes the calls, and
// JSONSerialization reads and writes the bodies, so there is no Ruby,
// no Python, and nothing to install. The app is known by its bundle id
// and nothing secret; the key and issuer ids come from the environment
// or from ~/.appstoreconnect/env.
//
// Idempotent by design: ensure-version finds an existing version before
// creating one, and metadata updates a locale that is present rather
// than duplicating it.
//
// It is also the only way Apple builds are signed and installed during
// development: install-devices, install-macos, install-ios,
// install-nfc-timing, install-pkcs11 and stamp replace every former shell
// install script.
//
// Usage:
//   apple-app-store-connect-release-manager.swift install-devices [options]
//   apple-app-store-connect-release-manager.swift install-macos [--check]
//   apple-app-store-connect-release-manager.swift purge-stale-registrations [--dry-run]
//   apple-app-store-connect-release-manager.swift install-ios [<device>]
//   apple-app-store-connect-release-manager.swift install-nfc-timing [<device>]
//   apple-app-store-connect-release-manager.swift install-pkcs11 [--check]
//   apple-app-store-connect-release-manager.swift stamp [--dry-run | --tag <channel>]
//   apple-app-store-connect-release-manager.swift capture-screenshots
//       [--platform macos|ios|ipad|all] [--locale fi|en-US|sv|all]
//       Captures every App Store screen from a demonstration launch and composes
//       Metadata/screenshots/<locale>/<DISPLAY_TYPE>/. See Metadata/screenshots/README.md.
//   apple-app-store-connect-release-manager.swift get <path>
//   apple-app-store-connect-release-manager.swift api <METHOD> <path> [json|-]
//   apple-app-store-connect-release-manager.swift app-id
//   apple-app-store-connect-release-manager.swift state
//   apple-app-store-connect-release-manager.swift builds <ios|macos>
//   apple-app-store-connect-release-manager.swift distribute <ios|macos> [group]
//   apple-app-store-connect-release-manager.swift add-tester <email> [group]
//   apple-app-store-connect-release-manager.swift invite <email>
//   apple-app-store-connect-release-manager.swift ensure-version <ios|macos> <versionString>
//   apple-app-store-connect-release-manager.swift attach-build <ios|macos> <versionString> <build>
//   apple-app-store-connect-release-manager.swift metadata <ios|macos> <versionString>
//   apple-app-store-connect-release-manager.swift app-info
//   apple-app-store-connect-release-manager.swift review-contact <ios|macos> <versionString>
//   apple-app-store-connect-release-manager.swift screenshots <ios|macos> <versionString>
//       Updates App Store version assets. TestFlight invitations use screenshots
//       from the latest approved version in Ready for Distribution.
//       See Documentation/release-runbook.md for screenshot visibility rules.
//   apple-app-store-connect-release-manager.swift age-rating
//   apple-app-store-connect-release-manager.swift export-compliance <ios|macos>
//   apple-app-store-connect-release-manager.swift pricing
//   apple-app-store-connect-release-manager.swift submissions
//   apple-app-store-connect-release-manager.swift submit <ios|macos> <versionString>

import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

// MARK: - Local release engineering

private struct ReleaseProcessResult {
  let status: Int32
  let stdout: String
  let stderr: String

  var combinedOutput: String {
    [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
  }
}

private func releaseFail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
  exit(1)
}

private func releaseNote(_ message: String) {
  print("  ok: \(message)")
}

@discardableResult
private func releaseRun(
  _ executable: String,
  _ arguments: [String],
  currentDirectory: URL? = nil,
  capture: Bool = false,
  allowFailure: Bool = false
) -> ReleaseProcessResult {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  process.currentDirectoryURL = currentDirectory

  let stdoutPipe = capture ? Pipe() : nil
  let stderrPipe = capture ? Pipe() : nil
  process.standardOutput = stdoutPipe
  process.standardError = stderrPipe

  do {
    try process.run()
  } catch {
    releaseFail("could not run \(executable): \(error.localizedDescription)")
  }

  let stdoutData = stdoutPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
  let stderrData = stderrPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
  process.waitUntilExit()

  let result = ReleaseProcessResult(
    status: process.terminationStatus,
    stdout: String(decoding: stdoutData, as: UTF8.self),
    stderr: String(decoding: stderrData, as: UTF8.self)
  )
  if result.status != 0 && !allowFailure {
    let command = ([executable] + arguments).joined(separator: " ")
    let detail = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    releaseFail(
      detail.isEmpty ? "command failed: \(command)" : "command failed: \(command)\n\(detail)")
  }
  return result
}

private let releaseFileManager = FileManager.default
private let releaseRepositoryRoot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .deletingLastPathComponent()

private func releaseReplace(_ destination: URL, with source: URL) {
  do {
    if releaseFileManager.fileExists(atPath: destination.path) {
      try releaseFileManager.removeItem(at: destination)
    }
    try releaseFileManager.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try releaseFileManager.moveItem(at: source, to: destination)
  } catch {
    releaseFail("could not replace \(destination.path): \(error.localizedDescription)")
  }
}

private func rappCargoTargetDirectory(at rustRoot: URL) -> URL {
  let result = releaseRun(
    "/usr/bin/env",
    ["cargo", "metadata", "--format-version", "1", "--no-deps"],
    currentDirectory: rustRoot,
    capture: true
  )
  do {
    guard
      let object = try JSONSerialization.jsonObject(with: Data(result.stdout.utf8))
        as? [String: Any],
      let path = object["target_directory"] as? String
    else {
      releaseFail("cargo metadata did not contain target_directory")
    }
    return URL(fileURLWithPath: path)
  } catch {
    releaseFail("could not read cargo metadata: \(error.localizedDescription)")
  }
}

private func releaseIsDirectory(_ url: URL) -> Bool {
  var isDirectory: ObjCBool = false
  return releaseFileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
    && isDirectory.boolValue
}

private func releaseDescendants(of root: URL) -> [URL] {
  guard
    let enumerator = releaseFileManager.enumerator(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
      options: [],
      errorHandler: { url, error in
        releaseFail("could not inspect \(url.path): \(error.localizedDescription)")
      }
    )
  else {
    releaseFail("could not enumerate \(root.path)")
  }

  var urls: [URL] = []
  while let url = enumerator.nextObject() as? URL {
    urls.append(url)
  }
  return urls
}

private func releasePlist(at url: URL) -> [String: Any] {
  do {
    let data = try Data(contentsOf: url)
    guard
      let plist = try PropertyListSerialization.propertyList(
        from: data,
        options: [],
        format: nil
      ) as? [String: Any]
    else {
      releaseFail("\(url.path) is not a dictionary property list")
    }
    return plist
  } catch {
    releaseFail("could not read \(url.path): \(error.localizedDescription)")
  }
}

private func releaseRegex(_ pattern: String, matches value: String) -> Bool {
  guard let expression = try? NSRegularExpression(pattern: pattern) else {
    releaseFail("invalid internal release regex: \(pattern)")
  }
  let range = NSRange(value.startIndex..<value.endIndex, in: value)
  return expression.firstMatch(in: value, range: range) != nil
}

private struct ReleaseArchiveLayout {
  let platform: String
  let app: URL
  let appExecutable: URL
  let appPlist: URL
  let appResources: URL
  let plugins: URL
  let tokenBundle: URL
  let rappBundle: URL
  let discoveryBundle: URL
  let tokenExecutable: URL
  let rappExecutable: URL
  let discoveryExecutable: URL
  let tokenPlist: URL
  let rappPlist: URL
  let discoveryPlist: URL
  let expectedArchitectures: Set<String>
  let hasRapp: Bool
  let hasDiscovery: Bool
}

private func releaseArchiveLayout(at archive: URL) -> ReleaseArchiveLayout {
  let app =
    archive
    .appendingPathComponent("Products")
    .appendingPathComponent("Applications")
    .appendingPathComponent("RefineID.app")
  guard releaseIsDirectory(app) else {
    releaseFail("expected exactly \(app.path)")
  }

  let contents = app.appendingPathComponent("Contents")
  if releaseIsDirectory(contents) {
    let plugins = contents.appendingPathComponent("PlugIns")
    let tokenBundle = plugins.appendingPathComponent("RefineIDTokenExtension.appex")
    let rappBundle = plugins.appendingPathComponent("RefineIDRappTokenExtension.appex")
    let discoveryBundle = plugins.appendingPathComponent("RefineIDDiscoveryExtension.appex")
    return ReleaseArchiveLayout(
      platform: "macOS",
      app: app,
      appExecutable: contents.appendingPathComponent("MacOS/RefineID"),
      appPlist: contents.appendingPathComponent("Info.plist"),
      appResources: contents.appendingPathComponent("Resources"),
      plugins: plugins,
      tokenBundle: tokenBundle,
      rappBundle: rappBundle,
      discoveryBundle: discoveryBundle,
      tokenExecutable: tokenBundle.appendingPathComponent("Contents/MacOS/RefineIDTokenExtension"),
      rappExecutable: rappBundle.appendingPathComponent(
        "Contents/MacOS/RefineIDRappTokenExtension"
      ),
      discoveryExecutable: discoveryBundle.appendingPathComponent(
        "Contents/MacOS/RefineIDDiscoveryExtension"
      ),
      tokenPlist: tokenBundle.appendingPathComponent("Contents/Info.plist"),
      rappPlist: rappBundle.appendingPathComponent("Contents/Info.plist"),
      discoveryPlist: discoveryBundle.appendingPathComponent("Contents/Info.plist"),
      expectedArchitectures: ["arm64"],
      // macOS carries the remote card as a requester that only dials out
      // (decisions 2026-10-10): the RAPP extension and the local-network
      // declarations ship, and nothing listens.
      hasRapp: true,
      hasDiscovery: false
    )
  }

  let plugins = app.appendingPathComponent("PlugIns")
  let tokenBundle = plugins.appendingPathComponent("RefineIDTokenExtension.appex")
  let rappBundle = plugins.appendingPathComponent("RefineIDRappTokenExtension.appex")
  let discoveryBundle = plugins.appendingPathComponent("RefineIDDiscoveryExtension.appex")
  return ReleaseArchiveLayout(
    platform: "iOS",
    app: app,
    appExecutable: app.appendingPathComponent("RefineID"),
    appPlist: app.appendingPathComponent("Info.plist"),
    appResources: app,
    plugins: plugins,
    tokenBundle: tokenBundle,
    rappBundle: rappBundle,
    discoveryBundle: discoveryBundle,
    tokenExecutable: tokenBundle.appendingPathComponent("RefineIDTokenExtension"),
    rappExecutable: rappBundle.appendingPathComponent("RefineIDRappTokenExtension"),
    discoveryExecutable: discoveryBundle.appendingPathComponent("RefineIDDiscoveryExtension"),
    tokenPlist: tokenBundle.appendingPathComponent("Info.plist"),
    rappPlist: rappBundle.appendingPathComponent("Info.plist"),
    discoveryPlist: discoveryBundle.appendingPathComponent("Info.plist"),
    expectedArchitectures: ["arm64"],
    // The first full version carries the remote card (owner decision
    // 2026-09-10), so an iOS candidate carries the RAPP extension
    // and the local-network declarations.
    hasRapp: true,
    hasDiscovery: true
  )
}

private func releaseEntitlements(of url: URL) -> [String: Any] {
  let result = releaseRun(
    "/usr/bin/codesign",
    ["-d", "--entitlements", "-", "--xml", url.path],
    capture: true,
    allowFailure: true
  )
  guard result.status == 0, !result.stdout.isEmpty else {
    releaseFail("\(url.path): no entitlements; the bundle is unsigned or unreadable")
  }
  do {
    guard
      let value = try PropertyListSerialization.propertyList(
        from: Data(result.stdout.utf8),
        options: [],
        format: nil
      ) as? [String: Any]
    else {
      releaseFail("\(url.path): entitlements are not a dictionary property list")
    }
    return value
  } catch {
    releaseFail("\(url.path): entitlements are not readable as a property list")
  }
}

private func releaseTeamIdentifier(of url: URL) -> String {
  let result = releaseRun(
    "/usr/bin/codesign",
    ["-dv", url.path],
    capture: true,
    allowFailure: true
  )
  for line in result.combinedOutput.split(whereSeparator: \.isNewline) {
    if line.hasPrefix("TeamIdentifier=") {
      return String(line.dropFirst("TeamIdentifier=".count))
    }
  }
  releaseFail("could not read the team identifier from \(url.path)")
}

private func releaseDeclaresAID(_ plistURL: URL) -> Bool {
  let plist = releasePlist(at: plistURL)
  let extensionDictionary = plist["NSExtension"] as? [String: Any]
  let attributes = extensionDictionary?["NSExtensionAttributes"] as? [String: Any]
  return attributes?["com.apple.ctk.aid"] != nil
}

private func releaseExtensionConfiguration(
  at plistURL: URL
) -> (point: String, attributes: [String: Any]) {
  let plist = releasePlist(at: plistURL)
  guard let extensionDictionary = plist["NSExtension"] as? [String: Any],
    let point = extensionDictionary["NSExtensionPointIdentifier"] as? String,
    let attributes = extensionDictionary["NSExtensionAttributes"] as? [String: Any]
  else {
    releaseFail("\(plistURL.path): incomplete NSExtension configuration")
  }
  return (point, attributes)
}

private func inspectReleaseArchive(_ archive: URL) {
  let layout = releaseArchiveLayout(at: archive)
  releaseNote("archive is \(layout.platform)")

  guard releaseIsDirectory(layout.tokenBundle) else {
    releaseFail("embedded extension missing: \(layout.tokenBundle.path)")
  }
  if layout.hasRapp {
    guard releaseIsDirectory(layout.rappBundle) else {
      releaseFail("embedded extension missing: \(layout.rappBundle.path)")
    }
  } else if releaseIsDirectory(layout.rappBundle) {
    releaseFail(
      "RAPP persistent-token extension is gated out of shipping "
        + "candidates: \(layout.rappBundle.path)"
    )
  }
  if layout.hasDiscovery {
    guard releaseIsDirectory(layout.discoveryBundle) else {
      releaseFail("embedded extension missing: \(layout.discoveryBundle.path)")
    }
  } else if releaseIsDirectory(layout.discoveryBundle) {
    releaseFail("discovery extension is iOS-only: \(layout.discoveryBundle.path)")
  }

  var executables = [layout.appExecutable, layout.tokenExecutable]
  var bundles = [layout.app, layout.tokenBundle]
  var extensions = [layout.tokenBundle]
  var extensionPlists = [layout.tokenPlist]
  if layout.hasRapp {
    executables.append(layout.rappExecutable)
    bundles.append(layout.rappBundle)
    extensions.append(layout.rappBundle)
    extensionPlists.append(layout.rappPlist)
  }
  if layout.hasDiscovery {
    executables.append(layout.discoveryExecutable)
    bundles.append(layout.discoveryBundle)
    extensions.append(layout.discoveryBundle)
    extensionPlists.append(layout.discoveryPlist)
  }

  let products = archive.appendingPathComponent("Products")
  let appCount = releaseDescendants(of: products).filter { url in
    guard url.pathExtension == "app", releaseIsDirectory(url) else {
      return false
    }
    let relative = url.path.dropFirst(products.path.count)
    return relative.split(separator: "/").count <= 2
  }.count
  guard appCount == 1 else {
    releaseFail("expected 1 .app in archive, found \(appCount)")
  }

  let pluginCount: Int
  do {
    pluginCount = try releaseFileManager.contentsOfDirectory(
      at: layout.plugins,
      includingPropertiesForKeys: nil
    ).count
  } catch {
    releaseFail("could not inspect \(layout.plugins.path): \(error.localizedDescription)")
  }
  let expectedPluginCount = 1 + (layout.hasRapp ? 1 : 0) + (layout.hasDiscovery ? 1 : 0)
  guard pluginCount == expectedPluginCount else {
    releaseFail("expected \(expectedPluginCount) plug-in(s), found \(pluginCount)")
  }
  releaseNote("one app, \(expectedPluginCount) embedded extension(s)")

  let expectedExecutablePaths = Set(executables.map(\.standardizedFileURL.path))
  var unexpectedMachO: [String] = []
  let descendants = releaseDescendants(of: layout.app)
  for url in descendants {
    let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
    guard values?.isRegularFile == true,
      !expectedExecutablePaths.contains(url.standardizedFileURL.path)
    else {
      continue
    }
    let result = releaseRun(
      "/usr/bin/file",
      ["-b", url.path],
      capture: true,
      allowFailure: true
    )
    if result.stdout.contains("Mach-O") {
      unexpectedMachO.append(url.path)
    }
  }
  guard unexpectedMachO.isEmpty else {
    releaseFail("unexpected Mach-O files:\n\(unexpectedMachO.joined(separator: "\n"))")
  }
  for forbidden in ["dylib", "framework", "so", "a"] {
    let hits = descendants.filter { $0.pathExtension == forbidden }.prefix(5)
    guard hits.isEmpty else {
      releaseFail(
        "forbidden *.\(forbidden) content:\n"
          + hits.map(\.path).joined(separator: "\n")
      )
    }
  }
  releaseNote("no unexpected executables, libraries, or frameworks")

  for executable in executables {
    let output = releaseRun(
      "/usr/bin/lipo",
      ["-archs", executable.path],
      capture: true
    ).stdout
    let architectures = Set(output.split(whereSeparator: \.isWhitespace).map(String.init))
    guard architectures == layout.expectedArchitectures else {
      releaseFail(
        "\(executable.path) architectures: "
          + "'\(architectures.sorted().joined(separator: " "))' "
          + "(expected \(layout.expectedArchitectures.sorted().joined(separator: " ")))"
      )
    }
  }
  releaseNote(
    "all binaries are \(layout.expectedArchitectures.sorted().joined(separator: " "))"
  )

  let forbiddenStrings =
    #"refineid-token-extension\.log|Uniffi callback interface .*handle missing in uniffiFree|\[(persistent-relay|persistent-token)\]|^(sign|session|discovery|mintFromPrime|createToken|supports|beginAuth|unseal|reader|prime): |^--(diagnostics|trace|reset-card-state|set-can|forget-can|prime)$"#
  for executable in executables {
    let output = releaseRun(
      "/usr/bin/strings",
      ["-a", executable.path],
      capture: true
    ).stdout
    let leaked = Array(
      Set(
        output.split(whereSeparator: \.isNewline)
          .map(String.init)
          .filter { releaseRegex(forbiddenStrings, matches: $0) }
      ).sorted().prefix(10)
    )
    guard leaked.isEmpty else {
      releaseFail(
        "\(executable.lastPathComponent): diagnostic or logging strings present:\n"
          + leaked.joined(separator: "\n")
      )
    }
  }
  releaseNote("no diagnostic or logging strings in any binary")

  for executable in executables {
    let output = releaseRun(
      "/usr/bin/otool",
      ["-l", executable.path],
      capture: true
    ).stdout
    let coverageCount = output.split(whereSeparator: \.isNewline).filter {
      $0.contains("__llvm_prf") || $0.contains("__llvm_cov")
    }.count
    guard coverageCount == 0 else {
      releaseFail(
        "\(executable.lastPathComponent): \(coverageCount) coverage sections present"
      )
    }
  }
  releaseNote("no coverage instrumentation")

  let entitlementRules: [(bundle: URL, allowed: Set<String>, required: Set<String>)]
  if layout.platform == "macOS" {
    let signingEntitlements: Set<String> = [
      "com.apple.application-identifier",
      "com.apple.developer.team-identifier",
      "com.apple.security.get-task-allow",
    ]
    // The client side carries timestamps, revocation fetches and, with
    // the remote card, the dial to the paired phone. A Mac never
    // listens, so no macOS bundle carries the server side.
    let appEntitlements: Set<String> = [
      "com.apple.security.app-sandbox",
      "com.apple.security.application-groups",
      "com.apple.security.files.user-selected.read-write",
      "com.apple.security.network.client",
      "com.apple.security.smartcard",
      "keychain-access-groups",
    ]
    var rules: [(bundle: URL, allowed: Set<String>, required: Set<String>)] = [
      (
        layout.app,
        signingEntitlements.union(appEntitlements),
        appEntitlements.subtracting(["keychain-access-groups"])
      ),
      (
        layout.tokenBundle,
        signingEntitlements.union([
          "com.apple.security.app-sandbox",
          "com.apple.security.application-groups",
          "com.apple.security.smartcard",
          "keychain-access-groups",
        ]),
        [
          "com.apple.security.app-sandbox",
          "com.apple.security.application-groups",
          "com.apple.security.smartcard",
        ]
      ),
    ]
    if layout.hasRapp {
      rules.append(
        (
          layout.rappBundle,
          signingEntitlements.union([
            "com.apple.security.app-sandbox",
            "com.apple.security.application-groups",
            "com.apple.security.network.client",
            "keychain-access-groups",
          ]),
          [
            "com.apple.security.app-sandbox",
            "com.apple.security.application-groups",
            "com.apple.security.network.client",
          ]
        )
      )
    }
    entitlementRules = rules
  } else {
    let allowed: Set<String> = [
      "keychain-access-groups",
      "com.apple.developer.nfc.readersession.formats",
      "application-identifier",
      "com.apple.developer.team-identifier",
      "get-task-allow",
    ]
    // The app alone raises the time-sensitive summons that brings the
    // holder to the phone when a paired computer needs the card.
    let appOnly: Set<String> = ["com.apple.developer.usernotifications.time-sensitive"]
    entitlementRules = bundles.map { bundle in
      (bundle, bundle == layout.app ? allowed.union(appOnly) : allowed, ["keychain-access-groups"])
    }
  }
  for rule in entitlementRules {
    let entitlements = releaseEntitlements(of: rule.bundle)
    let keys = Set(entitlements.keys)
    let missing = rule.required.subtracting(keys)
    guard missing.isEmpty else {
      releaseFail(
        "\(rule.bundle.path): missing \(missing.sorted().joined(separator: ", ")) entitlement"
      )
    }
    let stray = keys.subtracting(rule.allowed)
    guard stray.isEmpty else {
      releaseFail(
        "\(rule.bundle.path): unreviewed entitlements:\n"
          + stray.sorted().joined(separator: "\n")
      )
    }
  }
  if layout.platform == "macOS" {
    let appEntitlements = releaseEntitlements(of: layout.app)
    let readerEntitlements = releaseEntitlements(of: layout.tokenBundle)
    for entitlement in [
      "com.apple.security.network.client",
      "com.apple.security.network.server",
    ] {
      guard readerEntitlements[entitlement] == nil else {
        releaseFail(
          "\(layout.tokenBundle.path): direct-reader driver carries \(entitlement)"
        )
      }
    }
    if layout.hasRapp {
      let rappEntitlements = releaseEntitlements(of: layout.rappBundle)
      guard appEntitlements["com.apple.security.network.client"] as? Bool == true else {
        releaseFail("\(layout.app.path): missing RAPP entitlement com.apple.security.network.client")
      }
      guard rappEntitlements["com.apple.security.network.client"] as? Bool == true else {
        releaseFail(
          "\(layout.rappBundle.path): missing RAPP entitlement com.apple.security.network.client"
        )
      }
      // The Mac is always the requester: it dials the paired phone and
      // accepts nothing, so a server entitlement is a defect.
      for bundle in [layout.app, layout.rappBundle] {
        guard releaseEntitlements(of: bundle)["com.apple.security.network.server"] == nil else {
          releaseFail("\(bundle.path): network.server entitlement; a Mac never listens")
        }
      }
      guard rappEntitlements["com.apple.security.smartcard"] == nil else {
        releaseFail("\(layout.rappBundle.path): RAPP requester carries direct-card access")
      }
      releaseNote("RAPP and direct-reader entitlements are separated")
      releaseNote("no server entitlement; the Mac only dials the paired phone")
    } else {
      // A candidate without the remote card keeps outbound network
      // access for timestamps and revocation checks, and nothing
      // listens: a server entitlement in a build with no listener is
      // a question App Review is owed an answer to.
      guard appEntitlements["com.apple.security.network.client"] as? Bool == true else {
        releaseFail(
          "\(layout.app.path): missing com.apple.security.network.client; "
            + "timestamps and revocation checks need it"
        )
      }
      guard appEntitlements["com.apple.security.network.server"] == nil else {
        releaseFail("network.server entitlement present without the remote card")
      }
      releaseNote("no server entitlement; the remote card is gated off")
    }
  }
  releaseNote("entitlements match the reviewed allowlist")

  if layout.platform == "iOS" {
    let entitlements = releaseEntitlements(of: layout.app)
    guard let groups = entitlements["keychain-access-groups"] as? [String],
      let firstGroup = groups.first,
      firstGroup.hasSuffix(".fi.refineid.ReFineID")
    else {
      releaseFail("the app's own keychain access group is not first")
    }
    releaseNote("app's own keychain group is first (\(firstGroup))")
  }

  let appTeam = releaseTeamIdentifier(of: layout.app)
  for extensionBundle in extensions {
    let extensionTeam = releaseTeamIdentifier(of: extensionBundle)
    guard extensionTeam == appTeam else {
      releaseFail(
        "team mismatch: app '\(appTeam)' vs "
          + "\(extensionBundle.path) '\(extensionTeam)'"
      )
    }
  }
  releaseNote("app and embedded extensions signed by the same team (\(appTeam))")

  let appPlist = releasePlist(at: layout.appPlist)
  guard let appVersion = appPlist["CFBundleShortVersionString"] as? String,
    let appBuild = appPlist["CFBundleVersion"] as? String
  else {
    releaseFail("app version or build is missing from \(layout.appPlist.path)")
  }
  for plistURL in extensionPlists {
    let plist = releasePlist(at: plistURL)
    guard plist["CFBundleShortVersionString"] as? String == appVersion else {
      releaseFail("version mismatch: app \(appVersion) vs \(plistURL.path)")
    }
    guard plist["CFBundleVersion"] as? String == appBuild else {
      releaseFail("build mismatch: app \(appBuild) vs \(plistURL.path)")
    }
  }
  releaseNote("app and embedded extensions are version \(appVersion) (\(appBuild))")

  if layout.hasRapp {
    guard let localNetworkUsage = appPlist["NSLocalNetworkUsageDescription"] as? String,
      !localNetworkUsage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      releaseFail("NSLocalNetworkUsageDescription missing from the containing app")
    }
    guard let bonjourServices = appPlist["NSBonjourServices"] as? [String],
      bonjourServices.contains("_refineid-stream._tcp")
    else {
      releaseFail("NSBonjourServices does not declare _refineid-stream._tcp")
    }
    releaseNote("RAPP local-network privacy and Bonjour declarations are present")
  } else {
    // A candidate without the remote card must ask for nothing the
    // gated feature would have used: a local-network prompt string or
    // a Bonjour declaration in a build that never browses is a
    // question App Review is owed an answer to.
    guard appPlist["NSLocalNetworkUsageDescription"] == nil else {
      releaseFail("NSLocalNetworkUsageDescription present without the remote card")
    }
    guard appPlist["NSBonjourServices"] == nil else {
      releaseFail("NSBonjourServices present without the remote card")
    }
    releaseNote("no local-network or Bonjour declarations; the remote card is gated off")
  }

  let readerConfiguration = releaseExtensionConfiguration(at: layout.tokenPlist)
  guard readerConfiguration.point == "com.apple.ctk-tokens",
    readerConfiguration.attributes["com.apple.ctk.class-id"] as? String
      == "fi.refineid.ReFineID.token",
    readerConfiguration.attributes["com.apple.ctk.driver-class"] as? String
      == "RefineIDTokenExtension.TokenDriver",
    readerConfiguration.attributes["com.apple.ctk.token-type"] as? String
      == "smartcard"
  else {
    releaseFail("direct-reader CryptoTokenKit extension configuration is incorrect")
  }
  if layout.hasRapp {
    let rappConfiguration = releaseExtensionConfiguration(at: layout.rappPlist)
    guard rappConfiguration.point == "com.apple.ctk-tokens",
      rappConfiguration.attributes["com.apple.ctk.class-id"] as? String
        == "fi.refineid.ReFineID.rapp-token",
      rappConfiguration.attributes["com.apple.ctk.driver-class"] as? String
        == "RefineIDRappTokenExtension.PersistentTokenDriver",
      rappConfiguration.attributes["com.apple.ctk.token-type"] == nil
    else {
      releaseFail("RAPP persistent-token extension configuration is incorrect")
    }
    releaseNote("reader and RAPP CryptoTokenKit drivers are distinct")
  }

  if layout.platform == "iOS" {
    guard appPlist["MinimumOSVersion"] as? String == "26.0" else {
      releaseFail(
        "the iOS artifact does not require iOS 26.0; shipping "
          + "configurations demand it (Version.xcconfig)"
      )
    }
    guard let deviceFamily = appPlist["UIDeviceFamily"] as? [Int],
      deviceFamily == [1] || deviceFamily == [1, 2]
    else {
      releaseFail(
        "the iOS artifact targeted device family is invalid (Version.xcconfig)"
      )
    }
    guard let capabilities = appPlist["UIRequiredDeviceCapabilities"] as? [String],
      capabilities.contains("arm64")
    else {
      releaseFail("the iOS artifact does not declare arm64 requirement")
    }
    if deviceFamily == [1] {
      guard capabilities.contains("nfc") else {
        releaseFail("iPhone-only artifact must declare nfc capability")
      }
      releaseNote("iPhone-only artifact requiring iOS 26.0 and an NFC antenna")
    } else {
      releaseNote("Universal iPhone + iPad artifact requiring iOS 26.0 and arm64")
    }
    guard
      let usesNonExemptEncryption =
        appPlist["ITSAppUsesNonExemptEncryption"] as? Bool
    else {
      releaseFail("ITSAppUsesNonExemptEncryption missing from the app Info.plist")
    }
    if usesNonExemptEncryption {
      let code = appPlist["ITSEncryptionExportComplianceCode"] as? String
      guard let code, !code.isEmpty else {
        releaseFail(
          "ITSAppUsesNonExemptEncryption is true but "
            + "ITSEncryptionExportComplianceCode is missing. "
            + "App Store Connect rejects that upload with 90592."
        )
      }
      releaseNote("export compliance answered (non-exempt, code present)")
    } else {
      releaseNote("export compliance answered (exempt from documentation)")
    }
  }

  if layout.hasDiscovery {
    guard releaseDeclaresAID(layout.discoveryPlist) else {
      releaseFail(
        "discovery extension declares no com.apple.ctk.aid; no card is ever polled"
      )
    }
  }
  guard !releaseDeclaresAID(layout.tokenPlist) else {
    releaseFail("token extension declares com.apple.ctk.aid; the token will never be minted")
  }
  if layout.hasRapp, releaseDeclaresAID(layout.rappPlist) {
    releaseFail("RAPP persistent-token extension must not declare a card AID")
  }
  if layout.hasDiscovery {
    releaseNote("AID declared by the discovery extension only")
  } else {
    releaseNote("no AID declared; a Mac reader hands the card over without one")
  }

  let privacyManifest = layout.appResources.appendingPathComponent("PrivacyInfo.xcprivacy")
  guard releaseFileManager.fileExists(atPath: privacyManifest.path) else {
    releaseFail("missing PrivacyInfo.xcprivacy in app resources")
  }
  releaseNote("privacy manifest present")

  let quarantine = releaseRun(
    "/usr/bin/xattr",
    ["-rl", layout.app.path],
    capture: true,
    allowFailure: true
  ).combinedOutput
  let quarantined = quarantine.split(whereSeparator: \.isNewline).filter {
    $0.contains("com.apple.quarantine")
  }.prefix(5)
  guard quarantined.isEmpty else {
    releaseFail(
      "quarantined files in archive:\n"
        + quarantined.map(String.init).joined(separator: "\n")
    )
  }
  releaseNote("no quarantine attributes")

  let verification = releaseRun(
    "/usr/bin/codesign",
    ["--verify", "--deep", "--strict", layout.app.path],
    capture: true,
    allowFailure: true
  )
  guard verification.status == 0 else {
    releaseFail(
      verification.combinedOutput.isEmpty
        ? "codesign verification failed"
        : "codesign verification failed:\n\(verification.combinedOutput)"
    )
  }
  releaseNote("codesign verifies (deep, strict)")
  print("PASS: \(archive.path) (\(layout.platform))")
}

private enum ReleaseCandidatePlatform: String {
  case ios
  case macos

  var destination: String {
    switch self {
    case .ios: "generic/platform=iOS"
    case .macos: "generic/platform=macOS"
    }
  }
}

private struct ReleaseUploadCredentials {
  let keyID: String
  let issuerID: String
  let privateKeyPath: String
}

private func releaseEnvironment() -> [String: String] {
  var environment = ProcessInfo.processInfo.environment
  let home = releaseFileManager.homeDirectoryForCurrentUser.path
  let envURL = releaseFileManager.homeDirectoryForCurrentUser
    .appendingPathComponent(".appstoreconnect/env")
  guard let contents = try? String(contentsOf: envURL, encoding: .utf8) else {
    return environment
  }

  for originalLine in contents.split(whereSeparator: \.isNewline) {
    var line = originalLine.trimmingCharacters(in: .whitespaces)
    if line.hasPrefix("export ") {
      line.removeFirst("export ".count)
    }
    guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else {
      continue
    }
    let key = line[..<separator].trimmingCharacters(in: .whitespaces)
    var value = line[line.index(after: separator)...]
      .trimmingCharacters(in: .whitespaces)
    if value.count >= 2,
      (value.first == "\"" && value.last == "\"")
        || (value.first == "'" && value.last == "'")
    {
      value.removeFirst()
      value.removeLast()
    }
    environment[key] =
      value
      .replacingOccurrences(of: "$HOME", with: home)
      .replacingOccurrences(of: "~", with: home, options: [.anchored])
  }
  return environment
}

/// The credentials when the environment carries a complete set, nil
/// otherwise. Profile assurance wants them even on a local export;
/// only an upload hard-requires them.
private func releaseUploadCredentialsIfAvailable() -> ReleaseUploadCredentials? {
  let environment = releaseEnvironment()
  guard let keyID = environment["ASC_KEY_ID"], !keyID.isEmpty,
    let issuerID = environment["ASC_ISSUER_ID"], !issuerID.isEmpty
  else {
    return nil
  }
  let defaultPath = releaseFileManager.homeDirectoryForCurrentUser
    .appendingPathComponent(".appstoreconnect/private_keys/AuthKey_\(keyID).p8")
    .path
  let privateKeyPath = environment["ASC_PRIVATE_KEY_PATH"] ?? defaultPath
  guard releaseFileManager.fileExists(atPath: privateKeyPath) else {
    return nil
  }
  return ReleaseUploadCredentials(
    keyID: keyID,
    issuerID: issuerID,
    privateKeyPath: privateKeyPath
  )
}

private func releaseUploadCredentials() -> ReleaseUploadCredentials {
  guard let credentials = releaseUploadCredentialsIfAvailable() else {
    releaseFail(
      "ASC_KEY_ID, ASC_ISSUER_ID and the .p8 under "
        + "~/.appstoreconnect/private_keys are required for --upload")
  }
  return credentials
}

// MARK: - App Store Connect calls for release engineering

/// A short-lived ES256 token for the team API key.
private func releaseAPIToken(_ credentials: ReleaseUploadCredentials) -> String {
  guard let pem = try? String(contentsOfFile: credentials.privateKeyPath, encoding: .utf8),
    let key = try? P256.Signing.PrivateKey(pemRepresentation: pem)
  else {
    releaseFail("the .p8 at \(credentials.privateKeyPath) is not a readable P-256 key")
  }
  func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
  let now = Int(Date().timeIntervalSince1970)
  let header = ["alg": "ES256", "kid": credentials.keyID, "typ": "JWT"]
  let payload: [String: Any] = [
    "iss": credentials.issuerID, "iat": now, "exp": now + 1200,
    "aud": "appstoreconnect-v1",
  ]
  let headerData = try! JSONSerialization.data(withJSONObject: header)
  let payloadData = try! JSONSerialization.data(withJSONObject: payload)
  let signingInput = "\(base64URL(headerData)).\(base64URL(payloadData))"
  let signature = try! key.signature(for: Data(signingInput.utf8))
  return "\(signingInput).\(base64URL(signature.rawRepresentation))"
}

/// One synchronous JSON call; anything but success fails the release.
private func releaseAPI(
  _ method: String,
  _ path: String,
  body: [String: Any]? = nil,
  credentials: ReleaseUploadCredentials
) -> [String: Any] {
  var request = URLRequest(
    url: URL(string: "https://api.appstoreconnect.apple.com\(path)")!)
  request.httpMethod = method
  request.setValue(
    "Bearer \(releaseAPIToken(credentials))", forHTTPHeaderField: "Authorization")
  if let body {
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try! JSONSerialization.data(withJSONObject: body)
  }
  let waiter = DispatchSemaphore(value: 0)
  var received: (data: Data?, status: Int) = (nil, 0)
  URLSession.shared.dataTask(with: request) { data, response, _ in
    received = (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    waiter.signal()
  }.resume()
  waiter.wait()
  guard (200..<300).contains(received.status) else {
    let detail = received.data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    releaseFail("HTTP \(received.status) on \(method) \(path): \(detail)")
  }
  guard let data = received.data, !data.isEmpty,
    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  else {
    return [:]
  }
  return object
}

/// The app's and every embedded extension's bundle identifier.
private func releaseBundleIdentifiers(inArchive archive: URL) -> [String] {
  let layout = releaseArchiveLayout(at: archive)
  var plists = [layout.appPlist, layout.tokenPlist]
  if layout.hasRapp {
    plists.append(layout.rappPlist)
  }
  if layout.hasDiscovery {
    plists.append(layout.discoveryPlist)
  }
  return plists.compactMap {
    NSDictionary(contentsOf: $0)?["CFBundleIdentifier"] as? String
  }
}

/// Writes one profile where both current Xcode and the older tooling
/// location look for installed profiles.
private func releaseInstallProfile(content: String, uuid: String) {
  guard let blob = Data(base64Encoded: content) else {
    releaseFail("profile \(uuid) did not decode")
  }
  let home = releaseFileManager.homeDirectoryForCurrentUser
  for directory in [
    home.appendingPathComponent("Library/Developer/Xcode/UserData/Provisioning Profiles"),
    home.appendingPathComponent("Library/MobileDevice/Provisioning Profiles"),
  ] {
    try? releaseFileManager.createDirectory(
      at: directory, withIntermediateDirectories: true)
    try? blob.write(
      to: directory.appendingPathComponent("\(uuid).mobileprovision"),
      options: .atomic)
    try? blob.write(
      to: directory.appendingPathComponent("\(uuid).provisionprofile"),
      options: .atomic)
  }
}

/// Ensures every bundle in the archive has an ACTIVE App Store
/// profile - registering App IDs and minting profiles for first-time
/// targets - installs them, and returns the export signing map.
///
/// This exists because cloud signing refuses to create a profile for
/// this API key, while the very same key may create one by name.
private func releaseEnsureProfiles(
  archive: URL,
  platform: ReleaseCandidatePlatform,
  credentials: ReleaseUploadCredentials
) -> [String: String] {
  let identifiers = releaseBundleIdentifiers(inArchive: archive)
  let profileType = platform == .ios ? "IOS_APP_STORE" : "MAC_APP_STORE"
  let listing = releaseAPI(
    "GET",
    "/v1/profiles?filter[profileType]=\(profileType)&include=bundleId"
      + "&fields[bundleIds]=identifier"
      // bundleId must be listed as a field: naming any fields
      // strips every relationship that is not named with them.
      + "&fields[profiles]=name,uuid,profileState,profileContent,bundleId"
      + "&limit=200",
    credentials: credentials)
  var identifierByRecord: [String: String] = [:]
  for entry in listing["included"] as? [[String: Any]] ?? []
  where entry["type"] as? String == "bundleIds" {
    if let id = entry["id"] as? String,
      let identifier = (entry["attributes"] as? [String: Any])?["identifier"] as? String
    {
      identifierByRecord[id] = identifier
    }
  }
  struct StoredProfile {
    let name: String
    let uuid: String
    let content: String
  }
  var existing: [String: StoredProfile] = [:]
  for entry in listing["data"] as? [[String: Any]] ?? [] {
    let attributes = entry["attributes"] as? [String: Any] ?? [:]
    let profileID = entry["id"] as? String ?? ""
    let state = attributes["profileState"] as? String ?? ""
    let name = attributes["name"] as? String ?? ""
    let uuid = attributes["uuid"] as? String ?? ""
    let content = attributes["profileContent"] as? String ?? ""
    let relationship =
      ((entry["relationships"] as? [String: Any])?["bundleId"]
      as? [String: Any])?["data"] as? [String: Any]
    let record = relationship?["id"] as? String ?? ""
    let identifier = identifierByRecord[record]
    if state == "ACTIVE", let identifier, !uuid.isEmpty, !content.isEmpty {
      existing[identifier] = StoredProfile(name: name, uuid: uuid, content: content)
    } else if !profileID.isEmpty {
      _ = releaseAPI("DELETE", "/v1/profiles/\(profileID)", credentials: credentials)
      releaseNote("deleted stale/invalid profile \(name) (\(profileID))")
    }
  }

  var certificateID: String?
  func distributionCertificate() -> String {
    if let certificateID { return certificateID }
    let certificates =
      releaseAPI(
        "GET", "/v1/certificates?filter[certificateType]=DISTRIBUTION&limit=1",
        credentials: credentials)["data"] as? [[String: Any]] ?? []
    guard let id = certificates.first?["id"] as? String else {
      releaseFail("the team has no Apple Distribution certificate")
    }
    certificateID = id
    return id
  }

  func ensureBundleRecord(_ identifier: String) -> String {
    let matches =
      releaseAPI(
        "GET", "/v1/bundleIds?filter[identifier]=\(identifier)",
        credentials: credentials)["data"] as? [[String: Any]] ?? []
    if let record = matches.first(where: {
      ($0["attributes"] as? [String: Any])?["identifier"] as? String == identifier
    })?["id"] as? String {
      return record
    }
    let name = identifier.map { $0.isLetter || $0.isNumber ? $0 : " " }
      .reduce(into: "") { $0.append($1) }
    let created = releaseAPI(
      "POST", "/v1/bundleIds",
      body: [
        "data": [
          "type": "bundleIds",
          "attributes": [
            "identifier": identifier, "name": name, "platform": "UNIVERSAL",
          ],
        ]
      ],
      credentials: credentials)
    guard let record = (created["data"] as? [String: Any])?["id"] as? String else {
      releaseFail("registering the App ID \(identifier) returned no record")
    }
    releaseNote("registered App ID \(identifier)")
    return record
  }

  var map: [String: String] = [:]
  for identifier in identifiers {
    if let profile = existing[identifier] {
      releaseInstallProfile(content: profile.content, uuid: profile.uuid)
      map[identifier] = profile.name
      releaseNote("App Store profile present for \(identifier)")
      continue
    }
    let record = ensureBundleRecord(identifier)
    let profileName = "RefineID \(platform == .ios ? "iOS" : "Mac") App Store \(identifier)"
    let created = releaseAPI(
      "POST", "/v1/profiles",
      body: [
        "data": [
          "type": "profiles",
          "attributes": [
            "name": profileName,
            "profileType": profileType,
          ],
          "relationships": [
            "bundleId": ["data": ["type": "bundleIds", "id": record]],
            "certificates": [
              "data": [
                ["type": "certificates", "id": distributionCertificate()]
              ]
            ],
          ],
        ]
      ],
      credentials: credentials)
    guard
      let attributes = (created["data"] as? [String: Any])?["attributes"]
        as? [String: Any],
      let name = attributes["name"] as? String,
      let uuid = attributes["uuid"] as? String,
      let content = attributes["profileContent"] as? String
    else {
      releaseFail("creating the profile for \(identifier) returned no content")
    }
    releaseInstallProfile(content: content, uuid: uuid)
    map[identifier] = name
    releaseNote("minted App Store profile for \(identifier)")
  }
  return map
}

private func releaseWriteExportOptions(
  to destination: URL,
  platform: ReleaseCandidatePlatform,
  upload: Bool,
  provisioningProfiles: [String: String]? = nil
) {
  let source =
    releaseRepositoryRoot
    .appendingPathComponent("Config/ExportOptions-AppStore.plist")
  var options = releasePlist(at: source)
  if upload {
    options["destination"] = "upload"
  }
  // Named profiles the key just assured sign deterministically;
  // automatic signing cannot mint one for a first-time target.
  if let provisioningProfiles {
    options["signingStyle"] = "manual"
    options["signingCertificate"] = "Apple Distribution"
    if platform == .macos {
      options["installerSigningCertificate"] = "3rd Party Mac Developer Installer"
    }
    options["provisioningProfiles"] = provisioningProfiles
  }
  do {
    let data = try PropertyListSerialization.data(
      fromPropertyList: options,
      format: .xml,
      options: 0
    )
    try data.write(to: destination, options: .atomic)
  } catch {
    releaseFail("could not write \(destination.path): \(error.localizedDescription)")
  }
}

private func releaseCandidate(_ arguments: [String]) {
  var selection = "all"
  var sawSelection = false
  var upload = false
  for argument in arguments {
    switch argument {
    case "--upload":
      upload = true
    case "--no-upload":
      upload = false
    case "ios", "macos", "all":
      guard !sawSelection else {
        releaseFail("candidate accepts one of ios, macos, or all")
      }
      selection = argument
      sawSelection = true
    default:
      releaseFail("unknown candidate argument: \(argument)")
    }
  }

  let status = releaseRun(
    "/usr/bin/git",
    ["status", "--porcelain"],
    currentDirectory: releaseRepositoryRoot,
    capture: true
  ).stdout
  guard status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    releaseFail("the working tree is dirty; commit the exact release candidate first")
  }

  let (marketingVersion, buildNumber) = releaseCalendarVersion()
  let commit = releaseRun(
    "/usr/bin/git",
    ["rev-parse", "--short", "HEAD"],
    currentDirectory: releaseRepositoryRoot,
    capture: true
  ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)

  let platforms: [ReleaseCandidatePlatform]
  switch selection {
  case "ios":
    platforms = [.ios]
  case "macos":
    platforms = [.macos]
  default:
    platforms = [.ios, .macos]
  }
  let credentials =
    upload
    ? releaseUploadCredentials()
    : releaseUploadCredentialsIfAvailable()
  let outputRoot = releaseRepositoryRoot.appendingPathComponent("build/testflight")
  do {
    try releaseFileManager.createDirectory(
      at: outputRoot,
      withIntermediateDirectories: true
    )
  } catch {
    releaseFail("could not create \(outputRoot.path): \(error.localizedDescription)")
  }

  print(
    "Candidate \(marketingVersion) (\(buildNumber)), commit \(commit), "
      + (upload ? "upload enabled" : "local export only")
  )
  for platform in platforms {
    let archive = outputRoot.appendingPathComponent(
      "RefineID-\(platform.rawValue).xcarchive"
    )
    let exportDirectory = outputRoot.appendingPathComponent("export-\(platform.rawValue)")
    let exportOptions = outputRoot.appendingPathComponent(
      "ExportOptions-\(platform.rawValue).plist"
    )
    for disposable in [archive, exportDirectory, exportOptions] {
      if releaseFileManager.fileExists(atPath: disposable.path) {
        do {
          try releaseFileManager.removeItem(at: disposable)
        } catch {
          releaseFail(
            "could not remove \(disposable.path): \(error.localizedDescription)"
          )
        }
      }
    }

    print("Archiving \(platform.rawValue)...")
    releaseRun(
      "/usr/bin/xcodebuild",
      [
        "archive",
        "-project", "RefineID.xcodeproj",
        "-scheme", "RefineID",
        "-configuration", "TestFlight",
        "-destination", platform.destination,
        "-archivePath", archive.path,
        "MARKETING_VERSION=\(marketingVersion)",
        "CURRENT_PROJECT_VERSION=\(buildNumber)",
        "CLANG_ENABLE_CODE_COVERAGE=NO",
        "-quiet",
      ] + releaseSigningArguments(),
      currentDirectory: releaseRepositoryRoot
    )

    inspectReleaseArchive(archive)
    var provisioningProfiles: [String: String]?
    if let credentials {
      provisioningProfiles = releaseEnsureProfiles(
        archive: archive, platform: platform, credentials: credentials)
    }
    releaseWriteExportOptions(
      to: exportOptions,
      platform: platform,
      upload: upload,
      provisioningProfiles: provisioningProfiles)

    var exportArguments = [
      "-exportArchive",
      "-archivePath", archive.path,
      "-exportPath", exportDirectory.path,
      "-exportOptionsPlist", exportOptions.path,
      "-allowProvisioningUpdates",
      "-quiet",
    ]
    if let credentials {
      exportArguments += [
        "-authenticationKeyPath", credentials.privateKeyPath,
        "-authenticationKeyID", credentials.keyID,
        "-authenticationKeyIssuerID", credentials.issuerID,
      ]
    }
    print(upload ? "Uploading \(platform.rawValue)..." : "Exporting \(platform.rawValue)...")
    releaseRun(
      "/usr/bin/xcodebuild",
      exportArguments,
      currentDirectory: releaseRepositoryRoot
    )
    if upload {
      print("Syncing App Store metadata and screenshots for \(platform.rawValue)...")
      _ = ensureVersion(platform.rawValue, marketingVersion)
      pushMetadata(platform.rawValue, marketingVersion)
      pushScreenshots(platform.rawValue, marketingVersion)
    }
  }
  print("Candidate complete: \(marketingVersion) (\(buildNumber)), commit \(commit)")
}

// MARK: - App Store screenshots

/// One store locale: the folder App Store Connect reads, and the language
/// and region the app is captured in. A raw capture is named by its
/// language.
private struct StoreLocale {
  let folder: String
  let language: String
  let region: String
}

private let storeLocales = [
  StoreLocale(folder: "fi", language: "fi", region: "fi_FI"),
  StoreLocale(folder: "en-US", language: "en", region: "en_US"),
  StoreLocale(folder: "sv", language: "sv", region: "sv_SE"),
]

/// One screen the store shows: the raw capture it is composed from, and
/// the demonstration state the app is launched into for it. Every state
/// is a virtual card, so no capture reads a real card or a real holder.
private struct StoreScreen {
  let asset: String
  let arguments: [String]
}

/// The size of an image, in pixels.
private struct StorePixelSize: Equatable, CustomStringConvertible {
  let width: Int
  let height: Int

  var description: String { "\(width)x\(height)" }
}

/// The simulator one platform is captured on, found by its name and
/// created when missing. Its own device, so a capture never touches the
/// simulators used for testing.
private struct StoreSimulator {
  let name: String
  let deviceType: String
}

/// A platform in the store: its display type, the size App Store Connect
/// takes for it, and its screens in store order.
private enum StorePlatform: String, CaseIterable {
  case macos
  case ios
  case ipad

  var displayType: String {
    switch self {
    case .macos: "APP_DESKTOP"
    case .ios: "APP_IPHONE_67"
    case .ipad: "APP_IPAD_PRO_3GEN_129"
    }
  }

  var storeSize: StorePixelSize {
    switch self {
    case .macos: StorePixelSize(width: 2880, height: 1800)
    case .ios: StorePixelSize(width: 1290, height: 2796)
    case .ipad: StorePixelSize(width: 2048, height: 2732)
    }
  }

  var screens: [StoreScreen] {
    switch self {
    case .macos:
      [
        StoreScreen(asset: "window-card", arguments: ["--virtual-card", "activated-reader"]),
        StoreScreen(
          asset: "window-phone",
          arguments: ["--virtual-card", "activated-reader", "--mock-remote-connected"]),
      ]
    case .ios:
      [
        StoreScreen(
          asset: "iphone-main",
          arguments: ["--virtual-card", "registered-nfc", "--mock-remote-connected"]),
        StoreScreen(
          asset: "iphone-documents",
          arguments: ["--virtual-card", "registered-nfc", "--open-document-signing"]),
      ]
    case .ipad:
      [
        StoreScreen(
          asset: "ipad-main",
          arguments: ["--virtual-card", "activated-reader", "--mock-remote-connected"]),
        StoreScreen(
          asset: "ipad-documents",
          arguments: ["--virtual-card", "activated-reader", "--open-document-signing"]),
      ]
    }
  }

  /// The simulator that captures this platform, whose screen is the
  /// store size itself; nil for the Mac, captured as a window.
  var simulator: StoreSimulator? {
    switch self {
    case .macos:
      nil
    case .ios:
      StoreSimulator(
        name: "RefineID Store iPhone",
        deviceType: "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Plus")
    case .ipad:
      StoreSimulator(
        name: "RefineID Store iPad",
        deviceType: "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-12-9-inch-6th-generation-16GB")
    }
  }
}

private let storeScope = "capture-screenshots"
private let storeScreenshots = releaseRepositoryRoot.appendingPathComponent("Metadata/screenshots")
private let storeAssets = storeScreenshots.appendingPathComponent("assets")
private let storeBuildRoot = releaseRepositoryRoot.appendingPathComponent("build/store-screenshots")
private let storeComposer = releaseRepositoryRoot.appendingPathComponent(
  "Scripts/generate-store-screenshots.swift")
private let storeVirtualCardArgument = "--virtual-card"

/// A screen counts as settled once this many captures a second apart hold
/// the same pixels, and it gets this many captures to get there.
private let storeSettleInterval: TimeInterval = 1
private let storeStillCaptures = 3
private let storeSettleAttempts = 30

/// A capture shows content once anything differs between its top and
/// bottom tenths: a launch screen is one colour there. Every eighth pixel
/// of every eighth row is looked at.
private let storeContentBandDivisor = 10
private let storeContentSampleStride = 8

/// How long a launch may take to show its process and its window.
private let storeLaunchPolls = 100
private let storeLaunchPollInterval: TimeInterval = 0.2

/// How long a capture copy gets to quit before it is made to.
private let storeQuitPolls = 50
private let storeQuitPollInterval: useconds_t = 100_000

/// A Mac window captured below this many pixels per point was drawn on a
/// display too coarse for the store's canvas.
private let storeMacMinimumScale = 2

/// The smallest window height that is the status window rather than a
/// sliver of the menu bar.
private let storeMacMinimumWindowHeight = 100.0

/// The status bar every simulator capture shows.
private let storeStatusBar = [
  "--time", "9:41",
  "--dataNetwork", "wifi",
  "--wifiMode", "active", "--wifiBars", "3",
  "--cellularMode", "active", "--cellularBars", "4",
  "--batteryState", "charged", "--batteryLevel", "100",
]

/// The Mac's appearance, pinned for the one launch: dark, with standard
/// contrast and transparency whatever this Mac's accessibility settings
/// are, and no saved window state read or written in the container the
/// installed copy shares.
private let storeMacAppearanceArguments = [
  "-AppleInterfaceStyle", "Dark",
  "-increaseContrast", "NO",
  "-reduceTransparency", "NO",
  "-ApplePersistenceIgnoreState", "YES",
]

private let storeUsage =
  "usage: capture-screenshots [--platform macos|ios|ipad|all] [--locale fi|en-US|sv|all]"

/// What every capture launch says beside its screen's own state: no
/// development aids, no motion, and the locale's language and region.
private func storeLaunchArguments(_ screen: StoreScreen, _ locale: StoreLocale) -> [String] {
  screen.arguments + [
    "--hide-diagnostics", "--ui-test-disable-motion",
    "-AppleLanguages", "(\(locale.language))",
    "-AppleLocale", locale.region,
  ]
}

private func storeAsset(_ screen: StoreScreen, _ locale: StoreLocale) -> URL {
  storeAssets.appendingPathComponent("\(screen.asset)-\(locale.language).png")
}

private func storeImage(_ url: URL) -> CGImage? {
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
  return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// Whether a capture shows anything between its top and bottom tenths.
private func storeShowsContent(_ image: CGImage, pixels: Data) -> Bool {
  let bytesPerPixel = image.bitsPerPixel / 8
  let band = image.height / storeContentBandDivisor
  let rowStride = storeContentSampleStride * image.bytesPerRow
  let pixelStride = storeContentSampleStride * bytesPerPixel
  return pixels.withUnsafeBytes { bytes in
    let reference = band * image.bytesPerRow
    for row in stride(from: reference, to: (image.height - band) * image.bytesPerRow, by: rowStride) {
      for offset in stride(from: row, to: row + image.width * bytesPerPixel, by: pixelStride) {
        for byte in 0..<bytesPerPixel where bytes[offset + byte] != bytes[reference + byte] {
          return true
        }
      }
    }
    return false
  }
}

/// Captures until the screen shows content and holds still, so no image is
/// taken of a launch screen, mid-animation, or before its content arrived.
/// Answers why it failed, or nil.
private func storeSettledCapture(to destination: URL, capture: (URL) -> Void) -> String? {
  let scratch = releaseFileManager.temporaryDirectory
    .appendingPathComponent("refineid-store-\(UUID().uuidString)")
  do {
    try releaseFileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
  } catch {
    return "could not create \(scratch.path): \(error.localizedDescription)"
  }
  defer { try? releaseFileManager.removeItem(at: scratch) }
  var previous: Data?
  var still = 0
  for attempt in 0..<storeSettleAttempts {
    Thread.sleep(forTimeInterval: storeSettleInterval)
    let file = scratch.appendingPathComponent("\(attempt).png")
    capture(file)
    guard let image = storeImage(file), let data = image.dataProvider?.data,
      storeShowsContent(image, pixels: data as Data)
    else {
      previous = nil
      still = 0
      continue
    }
    let pixels = data as Data
    still = pixels == previous ? still + 1 : 1
    previous = pixels
    if still == storeStillCaptures {
      releaseReplace(destination, with: file)
      return nil
    }
  }
  return "\(destination.lastPathComponent) never showed still content"
}

// MARK: Mac window

/// The process running this executable, once it runs.
private func storeWaitForProcess(_ executable: String) -> pid_t? {
  for _ in 0..<storeLaunchPolls {
    let found = releaseRun("/usr/bin/pgrep", ["-f", executable], capture: true, allowFailure: true)
    if let line = found.stdout.split(separator: "\n").first, let pid = pid_t(line) {
      return pid
    }
    Thread.sleep(forTimeInterval: storeLaunchPollInterval)
  }
  return nil
}

/// The status window of a process: its largest on-screen window at the
/// normal level, and that window's size in points.
private func storeWaitForWindow(of pid: pid_t) -> (id: CGWindowID, width: Double)? {
  for _ in 0..<storeLaunchPolls {
    let windows =
      CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
      as? [[String: Any]] ?? []
    let candidates = windows.compactMap { info -> (id: CGWindowID, width: Double, area: Double)? in
      guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
        (info[kCGWindowLayer as String] as? Int) == 0,
        let number = info[kCGWindowNumber as String] as? CGWindowID,
        let bounds = info[kCGWindowBounds as String] as? [String: Double],
        let width = bounds["Width"], let height = bounds["Height"],
        height >= storeMacMinimumWindowHeight
      else { return nil }
      return (number, width, width * height)
    }
    if let window = candidates.max(by: { $0.area < $1.area }) {
      return (window.id, window.width)
    }
    Thread.sleep(forTimeInterval: storeLaunchPollInterval)
  }
  return nil
}

/// Quits a capture copy, and makes it quit if it will not.
private func storeStop(_ pid: pid_t) {
  kill(pid, SIGTERM)
  for _ in 0..<storeQuitPolls {
    if kill(pid, 0) != 0 { return }
    usleep(storeQuitPollInterval)
  }
  kill(pid, SIGKILL)
}

/// Captures the status window of one launch of the built copy. Answers
/// why it failed, or nil.
///
/// Every launch carries a virtual card, so the copy holds no card session
/// and runs beside the installed one without asking it to quit.
private func storeCaptureMacWindow(app: URL, arguments: [String], to destination: URL) -> String? {
  guard arguments.contains(storeVirtualCardArgument) else {
    return "a Mac capture launch must carry \(storeVirtualCardArgument)"
  }
  let executable = app.appendingPathComponent("Contents/MacOS/RefineID").path
  releaseRun("/usr/bin/pkill", ["-f", executable], capture: true, allowFailure: true)
  releaseRun("/usr/bin/open", ["-n", "-a", app.path, "--args"] + arguments)
  guard let pid = storeWaitForProcess(executable) else { return "the built copy did not start" }
  defer { storeStop(pid) }
  // Launched without saved state, the app presents no window. Opening the
  // running copy again presents it, as a click on its Dock icon does; the
  // arguments only matter should the copy have gone.
  Thread.sleep(forTimeInterval: storeSettleInterval)
  releaseRun("/usr/bin/open", ["-a", app.path, "--args"] + arguments)
  guard let window = storeWaitForWindow(of: pid) else { return "the built copy showed no window" }
  if let failure = storeSettledCapture(
    to: destination,
    capture: { file in
      releaseRun("/usr/sbin/screencapture", ["-x", "-l\(window.id)", file.path])
    })
  {
    return failure
  }
  guard let image = storeImage(destination),
    Double(image.width) >= Double(storeMacMinimumScale) * window.width
  else {
    return "\(destination.lastPathComponent) is below \(storeMacMinimumScale)x; "
      + "capture on a Retina display"
  }
  return nil
}

/// Builds the Mac app and captures every Mac screen in every locale.
///
/// The build is a second copy beside the installed one. Its token
/// extensions are unregistered once the captures are done, so the system
/// keeps choosing the installed copy's driver.
private func storeCaptureMac(_ locales: [StoreLocale]) {
  guard CGPreflightScreenCaptureAccess() else {
    releaseFail(
      "this terminal may not record the screen. Allow it under System Settings > "
        + "Privacy & Security > Screen & System Audio Recording, then run this again.")
  }
  let derivedData = storeBuildRoot.appendingPathComponent("macos")
  installNote(storeScope, "building Debug for macOS")
  releaseRun(
    "/usr/bin/xcodebuild",
    [
      "-project", "RefineID.xcodeproj",
      "-scheme", "RefineID",
      "-configuration", "Debug",
      "-destination", "platform=macOS,arch=arm64",
      "-derivedDataPath", derivedData.path,
      "CLANG_COVERAGE_MAPPING=NO",
      "ENABLE_CODE_COVERAGE=NO",
      "-quiet",
      "build",
    ] + releaseSigningArguments(),
    currentDirectory: releaseRepositoryRoot)
  let app = derivedData.appendingPathComponent("Build/Products/Debug/\(installMacName)")
  guard releaseIsDirectory(app) else { releaseFail("build produced no \(installMacName)") }
  for locale in locales {
    for screen in StorePlatform.macos.screens {
      let destination = storeAsset(screen, locale)
      if let failure = storeCaptureMacWindow(
        app: app,
        arguments: storeLaunchArguments(screen, locale) + storeMacAppearanceArguments,
        to: destination)
      {
        installUnregister(app)
        releaseFail(failure)
      }
      installNote(storeScope, "captured \(destination.lastPathComponent)")
    }
  }
  installUnregister(app)
}

// MARK: Simulators

private func storeSimulatorListing() -> [[String: Any]] {
  let listing = releaseRun(
    "/usr/bin/xcrun", ["simctl", "list", "devices", "available", "--json"], capture: true)
  guard
    let root = try? JSONSerialization.jsonObject(with: Data(listing.stdout.utf8))
      as? [String: Any],
    let runtimes = root["devices"] as? [String: [[String: Any]]]
  else { releaseFail("could not read the simulator list") }
  return runtimes.filter { $0.key.contains("iOS") }.values.flatMap(\.self)
}

/// The newest iOS runtime that runs a device type.
private func storeRuntime(for deviceType: String) -> String {
  let listing = releaseRun("/usr/bin/xcrun", ["simctl", "list", "runtimes", "--json"], capture: true)
  guard
    let root = try? JSONSerialization.jsonObject(with: Data(listing.stdout.utf8))
      as? [String: Any],
    let runtimes = root["runtimes"] as? [[String: Any]]
  else { releaseFail("could not read the simulator runtimes") }
  let fitting = runtimes.filter { runtime in
    runtime["platform"] as? String == "iOS"
      && runtime["isAvailable"] as? Bool == true
      && (runtime["supportedDeviceTypes"] as? [[String: Any]] ?? []).contains {
        $0["identifier"] as? String == deviceType
      }
  }
  let newest = fitting.max { first, second in
    (first["version"] as? String ?? "")
      .compare(second["version"] as? String ?? "", options: .numeric) == .orderedAscending
  }
  guard let identifier = newest?["identifier"] as? String else {
    releaseFail("no installed iOS runtime runs \(deviceType)")
  }
  return identifier
}

/// The simulator's identifier, created when missing, and whether it was
/// already running.
private func storeSimulatorDevice(_ simulator: StoreSimulator) -> (udid: String, wasBooted: Bool) {
  if let device = storeSimulatorListing().first(where: { $0["name"] as? String == simulator.name }),
    let udid = device["udid"] as? String
  {
    return (udid, device["state"] as? String == "Booted")
  }
  installNote(storeScope, "creating the simulator \(simulator.name)")
  let created = releaseRun(
    "/usr/bin/xcrun",
    [
      "simctl", "create", simulator.name, simulator.deviceType,
      storeRuntime(for: simulator.deviceType),
    ],
    capture: true)
  return (created.stdout.trimmingCharacters(in: .whitespacesAndNewlines), false)
}

/// Boots a simulator and settles everything a capture shows besides the
/// app: dark, standard contrast and text size.
private func storePrepareSimulator(_ udid: String) {
  releaseRun("/usr/bin/xcrun", ["simctl", "bootstatus", udid, "-b"], capture: true)
  for setting in [
    ["appearance", "dark"], ["increase_contrast", "disabled"], ["content_size", "large"],
  ] {
    releaseRun("/usr/bin/xcrun", ["simctl", "ui", udid] + setting, capture: true)
  }
}

/// Sets the simulator's language and region, which format the status
/// bar's time, and puts the status bar in place. The status bar reads them
/// once per boot, so the simulator restarts in between.
private func storeSetSimulatorLocale(_ udid: String, _ locale: StoreLocale) {
  for write in [
    ["AppleLocale", "-string", locale.region], ["AppleLanguages", "-array", locale.language],
  ] {
    releaseRun(
      "/usr/bin/xcrun", ["simctl", "spawn", udid, "defaults", "write", "-g"] + write,
      capture: true)
  }
  releaseRun("/usr/bin/xcrun", ["simctl", "shutdown", udid], capture: true)
  releaseRun("/usr/bin/xcrun", ["simctl", "bootstatus", udid, "-b"], capture: true)
  releaseRun(
    "/usr/bin/xcrun", ["simctl", "status_bar", udid, "override"] + storeStatusBar, capture: true)
}

/// Captures one screen on a simulator. Answers why it failed, or nil.
private func storeCaptureSimulatorScreen(
  _ udid: String, platform: StorePlatform, arguments: [String], to destination: URL
) -> String? {
  releaseRun(
    "/usr/bin/xcrun",
    ["simctl", "launch", "--terminate-running-process", udid, bundleID] + arguments,
    capture: true)
  if let failure = storeSettledCapture(
    to: destination,
    capture: { file in
      releaseRun(
        "/usr/bin/xcrun", ["simctl", "io", udid, "screenshot", "--type=png", file.path],
        capture: true)
    })
  {
    return failure
  }
  guard let image = storeImage(destination),
    StorePixelSize(width: image.width, height: image.height) == platform.storeSize
  else {
    return "\(destination.lastPathComponent) is not \(platform.storeSize)"
  }
  return platform == .ipad ? storeRemoveIPadDate(destination) : nil
}

/// Builds the app for the simulator and captures every screen of the
/// chosen platforms in every locale.
private func storeCaptureSimulators(_ platforms: [StorePlatform], _ locales: [StoreLocale]) {
  let devices = platforms.compactMap { platform -> (StorePlatform, String, Bool)? in
    guard let simulator = platform.simulator else { return nil }
    let device = storeSimulatorDevice(simulator)
    storePrepareSimulator(device.udid)
    return (platform, device.udid, device.wasBooted)
  }
  guard let first = devices.first else { return }
  let derivedData = storeBuildRoot.appendingPathComponent("ios")
  installNote(storeScope, "building Debug for the iOS simulator")
  releaseRun(
    "/usr/bin/xcodebuild",
    [
      "-project", "RefineID.xcodeproj",
      "-scheme", "RefineID",
      "-configuration", "Debug",
      "-destination", "platform=iOS Simulator,id=\(first.1)",
      "-derivedDataPath", derivedData.path,
      "CLANG_COVERAGE_MAPPING=NO",
      "ENABLE_CODE_COVERAGE=NO",
      "-quiet",
      "build",
    ],
    currentDirectory: releaseRepositoryRoot)
  let app = derivedData.appendingPathComponent("Build/Products/Debug-iphonesimulator/RefineID.app")
  guard releaseIsDirectory(app) else { releaseFail("build produced no simulator RefineID.app") }
  for (_, udid, _) in devices {
    // A fresh install starts every capture from the same empty state.
    releaseRun(
      "/usr/bin/xcrun", ["simctl", "uninstall", udid, bundleID], capture: true,
      allowFailure: true)
    releaseRun("/usr/bin/xcrun", ["simctl", "install", udid, app.path], capture: true)
  }
  for (platform, udid, _) in devices {
    for locale in locales {
      storeSetSimulatorLocale(udid, locale)
      for screen in platform.screens {
        let destination = storeAsset(screen, locale)
        if let failure = storeCaptureSimulatorScreen(
          udid, platform: platform, arguments: storeLaunchArguments(screen, locale),
          to: destination)
        {
          releaseFail(failure)
        }
        installNote(storeScope, "captured \(destination.lastPathComponent)")
      }
    }
  }
  for (_, udid, wasBooted) in devices {
    releaseRun(
      "/usr/bin/xcrun", ["simctl", "terminate", udid, bundleID], capture: true,
      allowFailure: true)
    if !wasBooted {
      releaseRun("/usr/bin/xcrun", ["simctl", "shutdown", udid], capture: true, allowFailure: true)
    }
  }
}

/// The iPad status bar's height, and the widest gap inside its time ("9:41
/// AM"), in pixels; the gap before the date is wider.
private let storeIPadStatusBarHeight = 54
private let storeIPadTimeGap = 16

/// A pixel that differs from the background by more than this, summed
/// over its three channels, is ink.
private let storeInkThreshold = 60

/// Paints over everything in the left half of an iPad status bar after the
/// time with the bar's own colour: the date, which would date the
/// screenshot, and the app's name. The time and the indicators stay.
/// Answers why it failed, or nil.
private func storeRemoveIPadDate(_ url: URL) -> String? {
  let channels = 4
  guard let image = storeImage(url),
    let space = CGColorSpace(name: CGColorSpace.sRGB),
    let context = CGContext(
      data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
      bytesPerRow: image.width * channels, space: space,
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
    let buffer = context.data
  else { return "could not read \(url.lastPathComponent)" }
  let width = image.width
  let height = image.height
  context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
  // Bitmap memory runs top down: row zero is the top of the screen.
  let pixels = buffer.bindMemory(to: UInt8.self, capacity: width * height * channels)
  let background = (0..<3).map { Int(pixels[$0]) }
  let inkColumns = (0..<(width / 2)).map { x in
    (0..<storeIPadStatusBarHeight).contains { y in
      let offset = (y * width + x) * channels
      return (0..<3).reduce(0) { $0 + abs(Int(pixels[offset + $1]) - background[$1]) }
        > storeInkThreshold
    }
  }
  guard let timeStart = inkColumns.firstIndex(of: true) else {
    return "\(url.lastPathComponent) shows no time in its status bar"
  }
  var timeEnd = timeStart
  var column = timeStart
  while column < inkColumns.count, column - timeEnd <= storeIPadTimeGap {
    if inkColumns[column] { timeEnd = column }
    column += 1
  }
  let maximum = 255.0
  context.setFillColor(
    red: Double(background[0]) / maximum, green: Double(background[1]) / maximum,
    blue: Double(background[2]) / maximum, alpha: 1)
  context.fill(
    CGRect(
      x: timeEnd + storeIPadTimeGap, y: height - storeIPadStatusBarHeight,
      width: width / 2 - timeEnd - storeIPadTimeGap, height: storeIPadStatusBarHeight))
  guard let patched = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
  else { return "could not write \(url.lastPathComponent)" }
  CGImageDestinationAddImage(destination, patched, nil)
  return CGImageDestinationFinalize(destination) ? nil : "could not write \(url.lastPathComponent)"
}

// MARK: Composition

/// Checks every composed image: the display type's size, no alpha, and one
/// image per screen.
private func storeVerify(_ platforms: [StorePlatform], _ locales: [StoreLocale]) {
  for locale in locales {
    for platform in platforms {
      let folder = storeScreenshots.appendingPathComponent(locale.folder)
        .appendingPathComponent(platform.displayType)
      let images =
        ((try? releaseFileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))
        ?? [])
        .filter { $0.pathExtension == "png" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
      guard images.count == platform.screens.count else {
        releaseFail(
          "\(folder.path) holds \(images.count) images for \(platform.screens.count) screens")
      }
      for image in images {
        guard let source = CGImageSourceCreateWithURL(image as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { releaseFail("could not read \(image.path)") }
        let size = StorePixelSize(width: width, height: height)
        guard size == platform.storeSize else {
          releaseFail("\(image.path) is \(size), not \(platform.storeSize)")
        }
        guard properties[kCGImagePropertyHasAlpha] as? Bool != true else {
          releaseFail("\(image.path) has an alpha channel")
        }
        let relative = image.path.replacingOccurrences(
          of: releaseRepositoryRoot.path + "/", with: "")
        installNote(storeScope, "\(relative) \(size)")
      }
    }
  }
}

/// `capture-screenshots`: launches the app in a demonstration state for
/// every chosen platform, screen and locale, captures the raw screens into
/// Metadata/screenshots/assets, composes the store images and checks them.
private func releaseCaptureScreenshots(_ arguments: [String]) {
  var platformChoice = "all"
  var localeChoice = "all"
  var remaining = arguments[...]
  while let argument = remaining.popFirst() {
    switch argument {
    case "--platform":
      platformChoice = remaining.popFirst() ?? ""
    case "--locale":
      localeChoice = remaining.popFirst() ?? ""
    default:
      releaseFail(storeUsage)
    }
  }
  let platforms =
    platformChoice == "all"
    ? StorePlatform.allCases : StorePlatform(rawValue: platformChoice).map { [$0] } ?? []
  let locales =
    localeChoice == "all" ? storeLocales : storeLocales.filter { $0.folder == localeChoice }
  guard !platforms.isEmpty, !locales.isEmpty else { releaseFail(storeUsage) }

  installHideFromSpotlight(storeBuildRoot)
  if platforms.contains(.macos) {
    storeCaptureMac(locales)
  }
  storeCaptureSimulators(platforms.filter { $0 != .macos }, locales)
  installNote(storeScope, "composing")
  releaseRun(
    "/usr/bin/xcrun",
    ["swift", storeComposer.path, "--platform", platformChoice, "--locale", localeChoice],
    currentDirectory: releaseRepositoryRoot,
    capture: true)
  storeVerify(platforms, locales)
  installNote(storeScope, "done")
}

// MARK: - Version stamp

/// The calendar version of a build cut now: YY.M.D and the UTC time of
/// day as HHMM, hour times one hundred plus the minute. UTC, so it is
/// monotonic across machines and never repeats an hour at the
/// daylight-saving fall-back.
private func releaseCalendarVersion() -> (marketing: String, build: Int) {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  let components = calendar.dateComponents(
    [.year, .month, .day, .hour, .minute],
    from: Date()
  )
  guard let year = components.year,
    let month = components.month,
    let day = components.day,
    let hour = components.hour,
    let minute = components.minute
  else {
    releaseFail("could not derive the UTC release version")
  }
  return (String(format: "%02d.%d.%d", year % 100, month, day), hour * 100 + minute)
}

private let releaseVersionConfig = releaseRepositoryRoot.appendingPathComponent(
  "Version.xcconfig")
private let releaseModuleVersion = releaseRepositoryRoot.appendingPathComponent(
  "PKCS11Bridge/Sources/PKCS11Bridge/ModuleVersion.swift")

private func releaseRead(_ url: URL) -> String {
  guard let text = try? String(contentsOf: url, encoding: .utf8) else {
    releaseFail("could not read \(url.path)")
  }
  return text
}

private func releaseWrite(_ text: String, to url: URL) {
  do {
    try text.write(to: url, atomically: true, encoding: .utf8)
  } catch {
    releaseFail("could not write \(url.path): \(error.localizedDescription)")
  }
}

/// Replaces the one line `pattern` matches, failing when it matches none:
/// a stamp that silently changed nothing would be found at the next release.
private func releaseReplaceLine(
  in text: String, pattern: String, with replacement: String, file: URL
) -> String {
  guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
  else {
    releaseFail("bad stamp pattern \(pattern)")
  }
  let range = NSRange(text.startIndex..., in: text)
  guard regex.numberOfMatches(in: text, range: range) == 1 else {
    releaseFail("stamp did not take in \(file.path); check its version line")
  }
  return regex.stringByReplacingMatches(
    in: text, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
}

/// Writes the version into both files that carry it: the build settings
/// every target inherits, and the PKCS#11 module's compile-time constant,
/// which it reports through the C API and cannot read from a bundle.
private func releaseStampFiles(marketing: String, build: Int) {
  let config = releaseReplaceLine(
    in: releaseReplaceLine(
      in: releaseRead(releaseVersionConfig),
      pattern: "^MARKETING_VERSION = .*$",
      with: "MARKETING_VERSION = \(marketing)",
      file: releaseVersionConfig),
    pattern: "^CURRENT_PROJECT_VERSION = .*$",
    with: "CURRENT_PROJECT_VERSION = \(build)",
    file: releaseVersionConfig)
  let module = releaseReplaceLine(
    in: releaseRead(releaseModuleVersion),
    pattern: "^(\\s*internal static let text = )\".*\"$",
    with: "  internal static let text = \"\(marketing).\(build)\"",
    file: releaseModuleVersion)
  releaseWrite(config, to: releaseVersionConfig)
  releaseWrite(module, to: releaseModuleVersion)
}

/// The two version files as they were before an install stamped them.
/// An install stamps so every installed build reports the minute it was
/// built in, and puts both files back on any exit: a stamp is never part
/// of a feature commit.
nonisolated(unsafe) private var releaseStampOriginals: [(URL, String)] = []

private func releaseRestoreStamp() {
  for (url, text) in releaseStampOriginals {
    try? text.write(to: url, atomically: true, encoding: .utf8)
  }
  releaseStampOriginals = []
}

private func releaseStampForInstall() -> (marketing: String, build: Int) {
  let version = releaseCalendarVersion()
  if releaseStampOriginals.isEmpty {
    releaseStampOriginals = [
      (releaseVersionConfig, releaseRead(releaseVersionConfig)),
      (releaseModuleVersion, releaseRead(releaseModuleVersion)),
    ]
    atexit { releaseRestoreStamp() }
    for interrupt in [SIGINT, SIGTERM, SIGHUP] {
      signal(interrupt) { _ in exit(130) }
    }
  }
  releaseStampFiles(marketing: version.marketing, build: version.build)
  return version
}

/// `stamp`: writes the version for a release cut by hand, and with
/// `--tag <channel>` tags the current commit once the stamp is committed.
/// Tagging is opt-in: a stamp only sets a build number, a tag asserts a
/// commit is a release for a named channel.
private func releaseStamp(_ arguments: [String]) {
  let version = releaseCalendarVersion()
  switch arguments {
  case ["--dry-run"]:
    print("would stamp \(version.marketing) (\(version.build))")

  case []:
    releaseStampFiles(marketing: version.marketing, build: version.build)
    print(
      "stamped \(version.marketing) (\(version.build)). Next: review the diff, commit, "
        + "then \(toolName).swift stamp --tag <dev|beta|rc>")

  case let tagged where tagged.count == 2 && tagged[0] == "--tag":
    let channel = tagged[1]
    guard ["dev", "beta", "rc"].contains(channel) else {
      releaseFail("--tag needs a channel: dev, beta or rc")
    }
    releaseStampFiles(marketing: version.marketing, build: version.build)
    let diff = releaseRun(
      "/usr/bin/git", ["diff", "--quiet", "--", "Version.xcconfig"],
      currentDirectory: releaseRepositoryRoot, allowFailure: true)
    guard diff.status == 0 else {
      releaseFail(
        "stamped \(version.marketing) (\(version.build)), NOT tagged: "
          + "commit the stamp first, then run this again")
    }
    let tag = "ios-v\(version.marketing)-\(channel).\(version.build)"
    releaseRun(
      "/usr/bin/git",
      ["tag", "-a", tag, "-m", "RefineID \(version.marketing) (\(version.build)), \(channel)"],
      currentDirectory: releaseRepositoryRoot)
    print("stamped and tagged \(tag). Push it with: git push origin \(tag)")

  default:
    releaseFail("usage: stamp [--dry-run | --tag <dev|beta|rc>]")
  }
}

// MARK: - Signing

/// The xcodebuild arguments every signed build carries.
///
/// With the team API key, Xcode registers any capability the entitlements
/// name on the App ID and regenerates the profile itself, with no Apple ID
/// signed in to Xcode. Without the key, provisioning falls back to the
/// account Xcode has.
private func releaseSigningArguments() -> [String] {
  var arguments = ["-allowProvisioningUpdates"]
  if let credentials = releaseUploadCredentialsIfAvailable() {
    arguments += [
      "-authenticationKeyPath", credentials.privateKeyPath,
      "-authenticationKeyID", credentials.keyID,
      "-authenticationKeyIssuerID", credentials.issuerID,
    ]
  }
  return arguments
}

// MARK: - Installs on this Mac

private let installMacName = "RefineID.app"
private let installMacTarget = URL(fileURLWithPath: "/Applications/RefineID.app")
private let installMacDerivedData = URL(fileURLWithPath: "/tmp/refineid-macos-install")
private let installLSRegister =
  "/System/Library/Frameworks/CoreServices.framework/Frameworks/"
  + "LaunchServices.framework/Support/lsregister"
private let installTokenExtensions = [
  "RefineIDTokenExtension", "RefineIDDiscoveryExtension", "RefineIDRappTokenExtension",
]

private func installNote(_ scope: String, _ message: String) {
  print("\(scope): \(message)")
}

/// Refuses anything the system will not launch: a broken seal, or a
/// certificate revoked since the bundle was signed. A revoked certificate
/// does not merely warn: launchd refuses to spawn the token extension
/// (POSIX 163), ctkd reports no token driver for a good card, and Safari
/// is never offered an identity, which looks exactly like an app bug.
private func installVerifySignature(_ bundle: URL, scope: String) {
  let result = releaseRun(
    "/usr/bin/codesign", ["--verify", "--deep", "--strict", bundle.path],
    capture: true, allowFailure: true)
  guard result.status == 0 else {
    print(result.combinedOutput)
    if result.combinedOutput.contains("CSSMERR_TP_CERT_REVOKED") {
      let identities = releaseRun(
        "/usr/bin/security", ["find-identity", "-v", "-p", "codesigning"],
        capture: true, allowFailure: true)
      print(identities.stdout)
      releaseFail(
        "the signing certificate is REVOKED: launchd will refuse to spawn the token "
          + "extension and Safari will never be offered an identity. Issue a new "
          + "development certificate and run this again.")
    }
    releaseFail("signature verification failed for \(bundle.path)")
  }
  let details = releaseRun(
    "/usr/bin/codesign", ["-dvv", bundle.path], capture: true, allowFailure: true)
  let authority =
    details.combinedOutput.split(separator: "\n")
    .first { $0.hasPrefix("Authority=") }
    .map { String($0.dropFirst("Authority=".count)) } ?? "unknown"
  installNote(scope, "signature valid: \(authority)")
}

/// Build products are not documents. Left indexed, every configuration of
/// every checkout answers a search for the app by name. The marker goes in
/// before the build, because a tree is indexed as it is written.
private func installHideFromSpotlight(_ directory: URL) {
  try? releaseFileManager.createDirectory(at: directory, withIntermediateDirectories: true)
  releaseFileManager.createFile(
    atPath: directory.appendingPathComponent(".metadata_never_index").path, contents: nil)
}

private func installPlugIns(of bundle: URL) -> [URL] {
  let plugIns = bundle.appendingPathComponent("Contents/PlugIns")
  let entries =
    (try? releaseFileManager.contentsOfDirectory(at: plugIns, includingPropertiesForKeys: nil))
    ?? []
  return entries.filter { $0.pathExtension == "appex" }.sorted { $0.path < $1.path }
}

private func installUnregister(_ bundle: URL) {
  if releaseFileManager.isExecutableFile(atPath: installLSRegister) {
    releaseRun(installLSRegister, ["-u", bundle.path], capture: true, allowFailure: true)
  }
  for plugIn in installPlugIns(of: bundle) {
    releaseRun("/usr/bin/pluginkit", ["-r", plugIn.path], capture: true, allowFailure: true)
  }
}

/// Every macOS copy outside /Applications is a competing CryptoTokenKit
/// driver registration; the system picks one silently, not necessarily the
/// one being edited. iOS build products carry no Contents/MacOS and are
/// only unregistered: Launch Services still lets them claim the identifier,
/// and a claimant without a macOS icon draws nothing in the Dock.
private func installRemoveStrayCopies(keeping built: URL) {
  var candidates = Set<String>()
  let spotlight = releaseRun(
    "/usr/bin/mdfind", ["-name", installMacName], capture: true, allowFailure: true)
  for line in spotlight.stdout.split(separator: "\n") where line.hasSuffix("/\(installMacName)") {
    candidates.insert(String(line))
  }
  let roots = [
    "/tmp", "/private/tmp",
    releaseFileManager.homeDirectoryForCurrentUser.path + "/Library/Developer/Xcode/DerivedData",
    releaseRepositoryRoot.appendingPathComponent("build").path,
    releaseRepositoryRoot.appendingPathComponent("derivedData").path,
  ]
  for root in roots where releaseIsDirectory(URL(fileURLWithPath: root)) {
    // Deep enough for a build nested in a scratch directory, which is
    // already nine levels down.
    let found = releaseRun(
      "/usr/bin/find", [root, "-maxdepth", "12", "-name", installMacName, "-type", "d"],
      capture: true, allowFailure: true)
    for line in found.stdout.split(separator: "\n") { candidates.insert(String(line)) }
  }
  let hidden = releaseRun(
    "/usr/bin/find",
    ["/Applications", "-maxdepth", "1", "-name", ".*\(installMacName)*", "-type", "d"],
    capture: true, allowFailure: true)
  for line in hidden.stdout.split(separator: "\n") { candidates.insert(String(line)) }

  let keep = built.resolvingSymlinksInPath().path
  var removed = 0
  for path in candidates.sorted() {
    let stray = URL(fileURLWithPath: path)
    guard path != installMacTarget.path, !path.contains(".xcarchive/"),
      stray.resolvingSymlinksInPath().path != keep
    else { continue }
    installUnregister(stray)
    guard releaseIsDirectory(stray.appendingPathComponent("Contents/MacOS")) else {
      installNote("install-macos", "unregistered non-macOS copy: \(path)")
      continue
    }
    installNote("install-macos", "removing stray macOS copy: \(path)")
    try? releaseFileManager.removeItem(at: stray)
    removed += 1
  }
  if removed == 0 { installNote("install-macos", "no stray macOS copies found") }
}

/// Build trees older than a week in the temporary directory, which are
/// scratch and not history. Age is the only evidence a tree is nobody's;
/// the tree this run uses and every git worktree are spared.
private func installRemoveStaleBuildTrees(sparing current: URL) {
  let worktrees = Set(
    releaseRun(
      "/usr/bin/git", ["worktree", "list", "--porcelain"],
      currentDirectory: releaseRepositoryRoot, capture: true, allowFailure: true
    ).stdout.split(separator: "\n")
      .filter { $0.hasPrefix("worktree ") }
      .map { String($0.dropFirst("worktree ".count)) })
  let found = releaseRun(
    "/usr/bin/find",
    [
      "/private/tmp", "-maxdepth", "1", "-mindepth", "1", "-iname", "refineid*",
      "-mmin", "+\(7 * 24 * 60)",
    ],
    capture: true, allowFailure: true)
  var removed = 0
  for path in found.stdout.split(separator: "\n").map(String.init).sorted() {
    guard path != current.path, path != "/private" + current.path, !worktrees.contains(path)
    else { continue }
    installNote("install-macos", "removing stale build tree: \(path)")
    try? releaseFileManager.removeItem(atPath: path)
    removed += 1
  }
  if removed == 0 { installNote("install-macos", "no stale build trees found") }
}

/// Ends every macOS RefineID process so the bundle can be replaced. Only
/// the macOS layout has Contents/MacOS, so a simulator install is spared.
private func installKillMacApp() {
  let pattern = "/RefineID.app/Contents/MacOS/RefineID"
  guard releaseRun("/usr/bin/pgrep", ["-f", pattern], capture: true, allowFailure: true).status
    == 0
  else { return }
  installNote("install-macos", "killing the running macOS app")
  releaseRun("/usr/bin/pkill", ["-KILL", "-f", pattern], capture: true, allowFailure: true)
  for _ in 0..<10 {
    if releaseRun("/usr/bin/pgrep", ["-f", pattern], capture: true, allowFailure: true).status
      != 0
    {
      return
    }
    usleep(100_000)
  }
}

/// A process left running on a replaced bundle answers nothing; ctkd then
/// waits ten seconds per request and the app hangs at launch.
private func installStopExtensions() {
  for name in installTokenExtensions {
    releaseRun(
      "/usr/bin/pkill", ["-f", "/\(name).appex/Contents/MacOS/\(name)"], capture: true,
      allowFailure: true)
  }
}

private func installCardIsInserted() -> Bool {
  releaseRun(
    "/usr/sbin/system_profiler", ["SPSmartCardsDataType"], capture: true, allowFailure: true
  ).stdout.contains("ATR:")
}

/// How long the restarted token watcher gets to mint the inserted card.
private let installTokenRemintSeconds = 25

/// CryptoTokenKit mints a reader card's token once per physical insertion
/// (Documentation/card-transports.md), so a card left in the reader across
/// a driver replacement keeps no token. The per-user token watcher reads
/// the slots afresh when it starts: ending it lets launchd start it on the
/// next request, and it mints the card with the new driver.
private func installRemintInsertedCard() {
  installNote("install-macos", "card in the reader; restarting the token watcher to mint it")
  releaseRun(
    "/usr/bin/pkill", ["-U", String(getuid()), "-x", "ctkd"], capture: true, allowFailure: true)
  for _ in 0..<installTokenRemintSeconds {
    sleep(1)
    let tokens = releaseRun(
      "/usr/bin/security", ["list-smartcards"], capture: true, allowFailure: true)
    if tokens.stdout.contains("fi.refineid") {
      installNote("install-macos", "card minted with the new driver")
      return
    }
  }
  installNote("install-macos", "card not minted; re-insert it")
}

private func installReportRegistrations() {
  installNote("install-macos", "registered CryptoTokenKit drivers for this app:")
  let plugins = releaseRun(
    "/usr/bin/pluginkit", ["-m", "-p", "com.apple.ctk-tokens", "-vvv"], capture: true,
    allowFailure: true)
  let lines = plugins.stdout.split(separator: "\n").filter { $0.contains("fi.refineid") }
  print(lines.isEmpty ? "  (none registered)" : lines.map { "  \($0)" }.joined(separator: "\n"))
}

private let installBundleIdentifier = "fi.refineid.ReFineID"

/// Every Launch Services record of the app or one of its extensions whose
/// bundle lies outside /Applications/RefineID.app, read from
/// `lsregister -dump`. A record lists `path:` before `identifier:`; the
/// path carries a trailing ` (0x...)` record reference. Local-network
/// privacy resolves the app's executable through these records, so a
/// leftover build product with the same identifier denies the installed
/// copy its local network access.
private func installStaleRegistrations() -> [String] {
  guard releaseFileManager.isExecutableFile(atPath: installLSRegister) else { return [] }
  let dump = releaseRun(installLSRegister, ["-dump"], capture: true, allowFailure: true)
  let recordSeparator = "--------"
  let pathKey = "path:"
  let identifierKey = "identifier:"
  let installed = installMacTarget.path
  var path: String?
  var stale = Set<String>()
  for rawLine in dump.stdout.split(separator: "\n", omittingEmptySubsequences: false) {
    let line = String(rawLine)
    if line.hasPrefix(recordSeparator) {
      path = nil
    } else if line.hasPrefix(pathKey) {
      var value = line.dropFirst(pathKey.count).trimmingCharacters(in: .whitespaces)
      if let reference = value.range(of: " (0x", options: .backwards), value.hasSuffix(")") {
        value = String(value[..<reference.lowerBound])
      }
      path = value
    } else if line.hasPrefix(identifierKey), let recordPath = path {
      let identifier = line.dropFirst(identifierKey.count).trimmingCharacters(in: .whitespaces)
      guard
        identifier == installBundleIdentifier
          || identifier.hasPrefix(installBundleIdentifier + ".")
      else { continue }
      guard recordPath != installed, !recordPath.hasPrefix(installed + "/") else { continue }
      stale.insert(recordPath)
    }
  }
  return stale.sorted()
}

/// Unregisters every stale record, then registers the installed copy
/// again so it is the only one Launch Services resolves. Files are left
/// where they are.
private func installPurgeStaleRegistrations(scope: String, dryRun: Bool) {
  let stale = installStaleRegistrations()
  if dryRun {
    for path in stale { installNote(scope, "would unregister: \(path)") }
    installNote(scope, "would unregister \(stale.count) stale copies")
    return
  }
  for path in stale {
    releaseRun(installLSRegister, ["-u", path], capture: true, allowFailure: true)
  }
  if releaseIsDirectory(installMacTarget) {
    releaseRun(installLSRegister, ["-f", installMacTarget.path], capture: true, allowFailure: true)
  }
  installNote(scope, "unregistered \(stale.count) stale copies")
}

/// `purge-stale-registrations`: the install step's Launch Services purge
/// on its own, without building or installing.
private func installPurgeStaleRegistrationsCommand(_ arguments: [String]) {
  switch arguments {
  case []:
    installPurgeStaleRegistrations(scope: "purge-stale-registrations", dryRun: false)
  case ["--dry-run"]:
    installPurgeStaleRegistrations(scope: "purge-stale-registrations", dryRun: true)
  default:
    releaseFail("usage: purge-stale-registrations [--dry-run]")
  }
}

/// `install-macos`: builds, verifies and installs RefineID into
/// /Applications, the only place a copy may live, then launches it.
/// The signature is checked before anything is replaced, so a bad
/// certificate leaves the working copy in place.
private func installMacOS(_ arguments: [String], stamp: Bool = true) {
  var configuration = "Debug"
  var checkOnly = false
  var remaining = arguments[...]
  while let argument = remaining.popFirst() {
    switch argument {
    case "--check":
      checkOnly = true
    case "--configuration":
      guard let value = remaining.popFirst() else {
        releaseFail("--configuration needs a value")
      }
      configuration = value
    default:
      releaseFail("usage: install-macos [--check] [--configuration NAME]")
    }
  }
  if checkOnly {
    guard releaseIsDirectory(installMacTarget) else {
      releaseFail("nothing installed at \(installMacTarget.path)")
    }
    installVerifySignature(installMacTarget, scope: "install-macos")
    installReportRegistrations()
    return
  }
  if stamp { _ = releaseStampForInstall() }

  for directory in [
    installMacDerivedData,
    releaseFileManager.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Developer/Xcode/DerivedData"),
    releaseRepositoryRoot.appendingPathComponent("build"),
    releaseRepositoryRoot.appendingPathComponent("derivedData"),
  ] {
    installHideFromSpotlight(directory)
  }

  installNote("install-macos", "building \(configuration) for macOS")
  releaseRun(
    "/usr/bin/xcodebuild",
    [
      "-project", "RefineID.xcodeproj",
      "-scheme", "RefineID",
      "-configuration", configuration,
      "-destination", "platform=macOS,arch=arm64",
      "-derivedDataPath", installMacDerivedData.path,
      "REFINEID_BUILD_SOURCE=\(installSourceTag())",
      "CLANG_COVERAGE_MAPPING=NO",
      "ENABLE_CODE_COVERAGE=NO",
      "-quiet",
      "build",
    ] + releaseSigningArguments(),
    currentDirectory: releaseRepositoryRoot)
  let built = installMacDerivedData.appendingPathComponent(
    "Build/Products/\(configuration)/\(installMacName)")
  guard releaseIsDirectory(built) else { releaseFail("build produced no \(installMacName)") }
  installVerifySignature(built, scope: "install-macos")

  installRemoveStrayCopies(keeping: built)
  installRemoveStaleBuildTrees(sparing: installMacDerivedData)
  installKillMacApp()
  let cardInserted = installCardIsInserted()
  installStopExtensions()

  installNote("install-macos", "installing to \(installMacTarget.path)")
  installUnregister(installMacTarget)
  try? releaseFileManager.removeItem(at: installMacTarget)
  do {
    try releaseFileManager.copyItem(at: built, to: installMacTarget)
  } catch {
    releaseFail("could not copy into \(installMacTarget.path): \(error.localizedDescription)")
  }
  installVerifySignature(installMacTarget, scope: "install-macos")

  // Registered directly: launching the app only so the system notices the
  // extensions put a window on screen and took it away on every install.
  var registered = false
  for plugIn in installPlugIns(of: installMacTarget) {
    if releaseRun("/usr/bin/pluginkit", ["-a", plugIn.path], capture: true, allowFailure: true)
      .status == 0
    {
      installNote("install-macos", "extension registered: \(plugIn.lastPathComponent)")
      registered = true
    }
  }
  if !registered {
    installNote("install-macos", "pluginkit refused; launching the app once so the system sees it")
    releaseRun("/usr/bin/open", ["-g", "-a", installMacTarget.path])
    sleep(3)
    installKillMacApp()
  }
  installPurgeStaleRegistrations(scope: "install-macos", dryRun: false)
  if cardInserted {
    installRemintInsertedCard()
  }
  installNote("install-macos", "launching \(installMacTarget.path)")
  releaseRun("/usr/bin/open", [installMacTarget.path])
  installNote("install-macos", "done.")
}

// MARK: - Installs on iPhone and iPad

private struct InstallDevice {
  let identifier: String
  let udid: String
  let name: String
}

/// The connected physical iPhones and iPads, read from devicectl's JSON
/// rather than its table, which is laid out for people.
private func installPhysicalDevices() -> [InstallDevice] {
  let output = releaseFileManager.temporaryDirectory
    .appendingPathComponent("refineid-devices-\(UUID().uuidString).json")
  defer { try? releaseFileManager.removeItem(at: output) }
  releaseRun(
    "/usr/bin/xcrun", ["devicectl", "list", "devices", "--json-output", output.path, "-q"],
    capture: true, allowFailure: true)
  guard let data = try? Data(contentsOf: output),
    let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
    let result = root["result"] as? [String: Any],
    let devices = result["devices"] as? [[String: Any]]
  else { return [] }
  return devices.compactMap { device in
    let hardware = device["hardwareProperties"] as? [String: Any] ?? [:]
    let connection = device["connectionProperties"] as? [String: Any] ?? [:]
    let properties = device["deviceProperties"] as? [String: Any] ?? [:]
    guard hardware["platform"] as? String == "iOS",
      hardware["reality"] as? String == "physical",
      connection["pairingState"] as? String == "paired",
      connection["tunnelState"] as? String != "unavailable",
      let identifier = device["identifier"] as? String,
      let udid = hardware["udid"] as? String
    else { return nil }
    return InstallDevice(
      identifier: identifier, udid: udid, name: properties["name"] as? String ?? identifier)
  }
}

private func installResolveDevice(_ requested: String?, scope: String) -> InstallDevice {
  let devices = installPhysicalDevices()
  if let requested {
    guard
      let match = devices.first(where: {
        [$0.identifier, $0.udid, $0.name].contains(requested)
      })
    else {
      releaseFail("\(scope): no connected iPhone or iPad named or identified \(requested)")
    }
    return match
  }
  guard let first = devices.first else {
    releaseFail("\(scope): no connected iPhone or iPad; pass a device name or identifier")
  }
  installNote(scope, "using \(first.name)")
  return first
}

/// Launches an installed app. A locked device cannot launch anything, and
/// that leaves a good install, so it is reported, not failed.
private func installLaunch(
  _ bundleID: String, on device: InstallDevice, scope: String, arguments: [String] = []
) {
  let launch = releaseRun(
    "/usr/bin/xcrun",
    [
      "devicectl", "device", "process", "launch", "--device", device.identifier,
      "--terminate-existing", bundleID,
    ] + arguments,
    capture: true, allowFailure: true)
  if launch.status == 0 {
    installNote(scope, "launched on \(device.name)")
  } else if launch.combinedOutput.contains("Locked") {
    installNote(scope, "installed on \(device.name); not launched because it is locked")
  } else {
    releaseFail("\(scope): launch failed on \(device.name)\n\(launch.combinedOutput)")
  }
}

/// Where this install is built from, for the development title: the
/// branch and commit when the checkout is not a clean main, empty when
/// it is. The install's own version stamp is not a change. A store
/// build never carries it.
private func installSourceTag() -> String {
  let branch = releaseRun(
    "/usr/bin/git", ["rev-parse", "--abbrev-ref", "HEAD"],
    currentDirectory: releaseRepositoryRoot, capture: true
  ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
  let commit = releaseRun(
    "/usr/bin/git", ["rev-parse", "--short", "HEAD"],
    currentDirectory: releaseRepositoryRoot, capture: true
  ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
  let dirty = !releaseRun(
    "/usr/bin/git",
    [
      "status", "--porcelain", "--untracked-files=no", "--",
      ".", ":!Version.xcconfig", ":!PKCS11Bridge/Sources/PKCS11Bridge/ModuleVersion.swift",
    ],
    currentDirectory: releaseRepositoryRoot, capture: true
  ).stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  if branch == "main", !dirty { return "" }
  return "\(branch)@\(commit)" + (dirty ? "+" : "")
}

/// Builds the optimized diagnostic configuration for one device, installs
/// and launches it. The version goes on the command line, which wins over
/// Version.xcconfig, so the device build edits no file.
private func installIOS(
  on device: InstallDevice, version: (marketing: String, build: Int), primeMockCard: Bool
) {
  let scope = "install-ios \(device.name)"
  let configuration = "Profile"
  let derivedData = URL(fileURLWithPath: "/tmp/refineid-ios-\(device.udid)")
  installNote(scope, "building RefineID \(version.marketing) (\(version.build)), \(configuration)")
  releaseRun(
    "/usr/bin/xcodebuild",
    [
      "-project", "RefineID.xcodeproj",
      "-scheme", "RefineID",
      "-configuration", configuration,
      "-destination", "platform=iOS,id=\(device.udid)",
      "-derivedDataPath", derivedData.path,
      "MARKETING_VERSION=\(version.marketing)",
      "CURRENT_PROJECT_VERSION=\(version.build)",
      "REFINEID_BUILD_SOURCE=\(installSourceTag())",
      "CLANG_COVERAGE_MAPPING=NO",
      "ENABLE_CODE_COVERAGE=NO",
      "-quiet",
      "build",
    ] + releaseSigningArguments(),
    currentDirectory: releaseRepositoryRoot)
  let app = derivedData.appendingPathComponent("Build/Products/\(configuration)-iphoneos/RefineID.app")
  releaseRun("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
  releaseRun(
    "/usr/bin/xcrun",
    ["devicectl", "device", "install", "app", "--device", device.identifier, app.path],
    capture: true)
  installNote(scope, "installed RefineID \(version.marketing) (\(version.build))")
  installLaunch(
    "fi.refineid.ReFineID", on: device, scope: scope,
    arguments: primeMockCard ? ["--prime-mock-card"] : [])
}

/// The iPad simulator a requester runs in: the 13-inch iPad Pro when
/// present, any iPad otherwise.
private func installIPadSimulator() -> String? {
  let listing = releaseRun(
    "/usr/bin/xcrun", ["simctl", "list", "devices", "available", "--json"], capture: true,
    allowFailure: true)
  guard let root = try? JSONSerialization.jsonObject(with: Data(listing.stdout.utf8))
    as? [String: Any],
    let runtimes = root["devices"] as? [String: [[String: Any]]]
  else { return nil }
  let iPads = runtimes.filter { $0.key.contains("iOS") }.values.flatMap { $0 }
    .filter { ($0["name"] as? String ?? "").contains("iPad") }
  let preferred =
    iPads.first { ($0["name"] as? String ?? "").contains("iPad Pro 13-inch") } ?? iPads.first
  return preferred?["udid"] as? String
}

private func installSimulator(_ simulator: String) {
  let scope = "install-simulator"
  let derivedData = URL(fileURLWithPath: "/tmp/refineid-ipad-sim")
  installNote(scope, "building Debug for iPad simulator \(simulator)")
  releaseRun(
    "/usr/bin/xcrun", ["simctl", "boot", simulator], capture: true, allowFailure: true)
  releaseRun(
    "/usr/bin/xcodebuild",
    [
      "-project", "RefineID.xcodeproj",
      "-scheme", "RefineID",
      "-configuration", "Debug",
      "-destination", "platform=iOS Simulator,id=\(simulator)",
      "-derivedDataPath", derivedData.path,
      "REFINEID_BUILD_SOURCE=\(installSourceTag())",
      "CLANG_COVERAGE_MAPPING=NO",
      "ENABLE_CODE_COVERAGE=NO",
      "-quiet",
      "build",
    ],
    currentDirectory: releaseRepositoryRoot)
  releaseRun(
    "/usr/bin/xcrun",
    [
      "simctl", "install", simulator,
      derivedData.appendingPathComponent("Build/Products/Debug-iphonesimulator/RefineID.app")
        .path,
    ])
  releaseRun(
    "/usr/bin/xcrun",
    ["simctl", "launch", "--terminate-running-process", simulator, "fi.refineid.ReFineID"],
    capture: true)
  releaseRun(
    "/usr/bin/open", ["-a", "Simulator", "--args", "-CurrentDeviceUDID", simulator],
    allowFailure: true)
  installNote(scope, "iPad simulator updated and running")
}

/// `install-ios`: one connected iPhone or iPad, the first one found when
/// none is named.
private func installIOSCommand(_ arguments: [String]) {
  var requested: String?
  var primeMockCard = false
  for argument in arguments {
    switch argument {
    case "--prime-mock-card": primeMockCard = true
    case let name where !name.hasPrefix("-") && requested == nil: requested = name
    default: releaseFail("usage: install-ios [<device name or identifier>] [--prime-mock-card]")
    }
  }
  installIOS(
    on: installResolveDevice(requested, scope: "install-ios"),
    version: releaseCalendarVersion(), primeMockCard: primeMockCard)
}

/// `install-devices`: this Mac, every connected iPhone and iPad, and the
/// iPad simulator, all on one version, built side by side. Run after a
/// feature commit so every machine that can run the app matches the tree.
private func installDevices(_ arguments: [String]) {
  var mac = true
  var devices = true
  var simulator = true
  var primeMockCard = false
  for argument in arguments {
    switch argument {
    case "--macos-only": (devices, simulator) = (false, false)
    case "--devices-only": (mac, simulator) = (false, false)
    case "--simulator-only": (mac, devices) = (false, false)
    case "--no-simulator": simulator = false
    case "--prime-mock-card": primeMockCard = true
    default:
      releaseFail(
        "usage: install-devices [--macos-only | --devices-only | --simulator-only | "
          + "--no-simulator] [--prime-mock-card]")
    }
  }
  let version = releaseStampForInstall()
  print("Installing RefineID \(version.marketing) (\(version.build))")

  var jobs: [() -> Void] = []
  if mac { jobs.append { installMacOS([], stamp: false) } }
  if devices {
    let found = installPhysicalDevices()
    if found.isEmpty { print("install-devices: no connected iPhone or iPad") }
    for device in found {
      jobs.append { installIOS(on: device, version: version, primeMockCard: primeMockCard) }
    }
  }
  if simulator {
    if let iPad = installIPadSimulator() {
      jobs.append { installSimulator(iPad) }
    } else {
      print("install-devices: no iPad simulator available")
    }
  }
  DispatchQueue.concurrentPerform(iterations: jobs.count) { jobs[$0]() }
  print("Installed RefineID \(version.marketing) (\(version.build)) on every selected target.")
}

/// `install-nfc-timing`: the NFC card timing sample in Samples/NFCCardTiming.
/// Its project is generated from project.yml, so the YAML stays the source.
private func installNFCTiming(_ arguments: [String]) {
  guard arguments.count <= 1 else {
    releaseFail("usage: install-nfc-timing [<device name or identifier>]")
  }
  let scope = "install-nfc-timing"
  let device = installResolveDevice(arguments.first, scope: scope)
  let sample = releaseRepositoryRoot.appendingPathComponent("Samples/NFCCardTiming")
  let derivedData = URL(fileURLWithPath: "/tmp/refineid-nfc-card-timing")
  releaseRun("/usr/bin/env", ["xcodegen", "generate", "--quiet"], currentDirectory: sample)
  installNote(scope, "building NFCCardTiming (Release) for \(device.name)")
  releaseRun(
    "/usr/bin/xcodebuild",
    [
      "-project", sample.appendingPathComponent("NFCCardTiming.xcodeproj").path,
      "-scheme", "NFCCardTiming",
      "-configuration", "Release",
      "-destination", "platform=iOS,id=\(device.udid)",
      "-derivedDataPath", derivedData.path,
      "-quiet",
      "build",
    ] + releaseSigningArguments(),
    currentDirectory: releaseRepositoryRoot)
  let app = derivedData.appendingPathComponent("Build/Products/Release-iphoneos/NFCCardTiming.app")
  releaseRun("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
  releaseRun(
    "/usr/bin/xcrun",
    ["devicectl", "device", "install", "app", "--device", device.identifier, app.path],
    capture: true)
  installLaunch("fi.refineid.NFCCardTiming", on: device, scope: scope)
}

// MARK: - PKCS#11 module on this Mac

/// `install-pkcs11`: builds the PKCS#11 bridge and installs it to
/// /usr/local/lib, inside ssh-agent's default provider allowlist; /usr/lib
/// is sealed by SIP. The same binary is installed under two names, since
/// the module behaves as authentication-only or full by the name it is
/// loaded under. Each copy gets its installed path as install name and an
/// ad-hoc signature, because install_name_tool invalidates the build's.
private func installPKCS11(_ arguments: [String]) {
  let scope = "install-pkcs11"
  let installDirectory = URL(fileURLWithPath: "/usr/local/lib")
  let names = ["librefineid_pkcs11.dylib", "librefineid_pkcs11_sign.dylib"]
  let superseded = ["librefineid_pkcs11_signing.dylib"]
  let package = releaseRepositoryRoot.appendingPathComponent("PKCS11Bridge")
  let built = package.appendingPathComponent(".build/release/libPKCS11Bridge.dylib")
  let primary = installDirectory.appendingPathComponent(names[0])
  let writable = releaseFileManager.isWritableFile(atPath: installDirectory.path)

  func privileged(_ executable: String, _ arguments: [String]) {
    if writable {
      releaseRun(executable, arguments)
    } else {
      releaseRun("/usr/bin/sudo", [executable] + arguments)
    }
  }

  // A missing card is not a failure; the module is still installed.
  func smokeTest() {
    installNote(scope, "smoke test: ssh-keygen -D \(primary.path)")
    let keys = releaseRun(
      "/usr/bin/ssh-keygen", ["-D", primary.path], capture: true, allowFailure: true)
    if keys.status == 0, !keys.stdout.isEmpty {
      print(keys.stdout)
      installNote(scope, "card keys listed")
    } else {
      installNote(scope, "no card keys listed; insert the card and run: ssh-keygen -D \(primary.path)")
    }
  }

  switch arguments {
  case ["--check"]:
    for name in names {
      let target = installDirectory.appendingPathComponent(name)
      guard releaseFileManager.fileExists(atPath: target.path) else {
        releaseFail("nothing installed at \(target.path)")
      }
      releaseRun("/usr/bin/codesign", ["--verify", target.path])
      installNote(scope, "installed: \(target.path)")
    }
    smokeTest()
    return
  case []:
    break
  default:
    releaseFail("usage: install-pkcs11 [--check]")
  }

  installNote(scope, "building release")
  releaseRun("/usr/bin/swift", ["build", "-c", "release"], currentDirectory: package)
  guard releaseFileManager.fileExists(atPath: built.path) else {
    releaseFail("build produced no \(built.path)")
  }
  for name in names {
    let target = installDirectory.appendingPathComponent(name)
    let staged = package.appendingPathComponent(".build/release/\(name)")
    try? releaseFileManager.removeItem(at: staged)
    do {
      try releaseFileManager.copyItem(at: built, to: staged)
    } catch {
      releaseFail("could not stage \(name): \(error.localizedDescription)")
    }
    releaseRun("/usr/bin/install_name_tool", ["-id", target.path, staged.path])
    releaseRun("/usr/bin/codesign", ["--force", "--sign", "-", staged.path], capture: true)
    releaseRun("/usr/bin/codesign", ["--verify", staged.path])
    if !writable { releaseRun("/usr/bin/sudo", ["/usr/bin/install", "-d", "-m", "0755", installDirectory.path]) }
    privileged("/usr/bin/install", ["-m", "0755", staged.path, target.path])
    installNote(scope, "installed: \(target.path)")
  }
  for name in superseded {
    let target = installDirectory.appendingPathComponent(name)
    guard releaseFileManager.fileExists(atPath: target.path) else { continue }
    installNote(scope, "removing superseded \(target.path)")
    privileged("/bin/rm", ["-f", target.path])
  }
  smokeTest()
  installNote(scope, "done. ssh usage: ssh -o PKCS11Provider=\(primary.path) user@host")
  installNote(
    scope,
    "signing consumers (SunPKCS11/DSS) load: \(installDirectory.appendingPathComponent(names[1]).path)")
}

private func printReleaseManagerUsage() {
  print(
    """
    Usage: Scripts/apple-app-store-connect-release-manager.swift <command> [arguments]

    Local install commands (builds signed with the App Store Connect API key, so
    entitlement capabilities are provisioned without an Apple ID in Xcode):
      install-devices [--macos-only|--devices-only|--simulator-only|--no-simulator] [--prime-mock-card]
          Install one version on this Mac, every connected iPhone and iPad, and the
          iPad simulator. Run after a feature commit.
      install-macos [--check] [--configuration NAME]
          Build, verify and install into /Applications, removing every stray copy.
      purge-stale-registrations [--dry-run]
          Unregister every Launch Services record of the app or its extensions
          outside /Applications/RefineID.app. --dry-run lists them only.
      install-ios [<device>] [--prime-mock-card]
          Build the optimized diagnostic build for one connected iPhone or iPad.
      install-nfc-timing [<device>]
          Install the NFC card timing sample on one connected device.
      install-pkcs11 [--check]
          Build and install the PKCS#11 module into /usr/local/lib.
      stamp [--dry-run | --tag <dev|beta|rc>]
          Write the calendar version into Version.xcconfig and the PKCS#11 module.
          Installs stamp for the build and restore both files afterwards.

    Local release commands:
      candidate [ios|macos|all] [--upload]
          Archive, inspect, and export a clean-tree candidate. Upload is opt-in.
      inspect-archive <path-to-xcarchive>
          Apply every reviewed archive gate without uploading or changing App Store state.
      capture-screenshots [--platform macos|ios|ipad|all] [--locale fi|en-US|sv|all]
          Capture every App Store screen from a demonstration launch (Mac window,
          iPhone and iPad simulators) and compose the store images. Default: all.

    App Store Connect commands:
      distribute <ios|macos> <group> [build-id]
          Distribute a processed TestFlight build; internal groups need no beta review.
      get, api, app-id, state, builds, add-tester, remove-tester, invite
      ensure-version, attach-build, metadata, app-info, review-contact
      screenshots, age-rating, export-compliance, pricing, submissions, submit

    Screenshot visibility:
      screenshots updates App Store version assets, not beta build assets.
      TestFlight invitations use the latest approved Ready for Distribution version.
      Draft screenshots and new beta builds do not update invitation screenshots.
      See Documentation/release-runbook.md for sources and verification steps.
    """
  )
}

let bundleID = "fi.refineid.ReFineID"
let apiBase = "https://api.appstoreconnect.apple.com"
let platforms = ["ios": "IOS", "macos": "MAC_OS"]

// What this file is called, read from how it was invoked so a rename
// cannot leave a failure naming something that no longer exists.
let toolName = URL(fileURLWithPath: CommandLine.arguments.first ?? "release")
  .deletingPathExtension().lastPathComponent

func die(_ message: String) -> Never {
  FileHandle.standardError.write(Data("\(toolName): \(message)\n".utf8))
  exit(1)
}

// The key and issuer ids, from the environment or the file beside the
// .p8, so an upload does not need them exported by hand.
func loadEnvironment() -> [String: String] {
  var values = ProcessInfo.processInfo.environment
  let path = ("~/.appstoreconnect/env" as NSString).expandingTildeInPath
  guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
    return values
  }
  for var line in text.split(separator: "\n").map(String.init) {
    line = line.trimmingCharacters(in: .whitespaces)
    if line.hasPrefix("export ") { line.removeFirst("export ".count) }
    guard !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { continue }
    let key = String(line[..<equals]).trimmingCharacters(in: .whitespaces)
    let value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
    if values[key] == nil { values[key] = value }
  }
  return values
}

let environment = loadEnvironment()
func required(_ name: String) -> String {
  guard let value = environment[name], !value.isEmpty else { die("\(name) is not set") }
  return value
}

extension Data {
  var base64URL: String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

// The API token, minted once with CryptoKit and reused. The .p8 is a
// PKCS#8 P-256 private key; a P-256 signature's raw representation is
// r||s, which is exactly the ES256 JWS form.
let token: String = {
  let keyID = required("ASC_KEY_ID")
  let issuer = required("ASC_ISSUER_ID")
  let keyPath = ("~/.appstoreconnect/private_keys/AuthKey_\(keyID).p8" as NSString)
    .expandingTildeInPath
  guard let pem = try? String(contentsOfFile: keyPath, encoding: .utf8) else {
    die("no key at \(keyPath); download the .p8 from App Store Connect")
  }
  guard let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else {
    die("the .p8 at \(keyPath) is not a readable P-256 key")
  }
  let now = Int(Date().timeIntervalSince1970)
  let header = ["alg": "ES256", "kid": keyID, "typ": "JWT"]
  let payload: [String: Any] = [
    "iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1",
  ]
  let headerData = try! JSONSerialization.data(withJSONObject: header)
  let payloadData = try! JSONSerialization.data(withJSONObject: payload)
  let signingInput = "\(headerData.base64URL).\(payloadData.base64URL)"
  let signature = try! key.signature(for: Data(signingInput.utf8))
  return "\(signingInput).\(signature.rawRepresentation.base64URL)"
}()

// One API call. Returns the parsed body, or exits with the API's own
// error on a non-2xx response. Brackets in a path (filter[bundleId])
// are percent-encoded, which URL rejects unencoded.
@discardableResult
func api(_ method: String, _ path: String, body: [String: Any]? = nil) -> [String: Any] {
  let encoded = path.replacingOccurrences(of: "[", with: "%5B")
    .replacingOccurrences(of: "]", with: "%5D")
  guard let url = URL(string: apiBase + encoded) else { die("bad path: \(path)") }
  var request = URLRequest(url: url)
  request.httpMethod = method
  request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
  if let body {
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try! JSONSerialization.data(withJSONObject: body)
  }
  let semaphore = DispatchSemaphore(value: 0)
  var data = Data()
  var status = 0
  URLSession.shared.dataTask(with: request) { responseData, response, _ in
    data = responseData ?? Data()
    status = (response as? HTTPURLResponse)?.statusCode ?? 0
    semaphore.signal()
  }.resume()
  semaphore.wait()
  guard (200..<300).contains(status) else {
    die("HTTP \(status) on \(method) \(path): \(String(data: data, encoding: .utf8) ?? "")")
  }
  if data.isEmpty { return [:] }
  return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
}

// Prints a response the way a person reads it.
func printJSON(_ object: [String: Any]) {
  guard !object.isEmpty else { return }
  let pretty = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
  print(String(data: pretty, encoding: .utf8) ?? "")
}

// A request body from an argument, or from stdin when it is "-".
//
// The one-off calls a release needs - reading what an endpoint holds,
// patching an attribute the named commands do not cover - used to go
// through a shell wrapper around curl and a Ruby token minter. They are
// the same call this file already makes, so they are made here.
func readBody(_ argument: String) -> [String: Any] {
  let text =
    argument == "-"
    ? String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    : argument
  guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
    let body = object as? [String: Any]
  else { die("the body is not a JSON object") }
  return body
}

func apiPlatform(_ name: String) -> String {
  guard let value = platforms[name] else { die("platform is ios or macos, not '\(name)'") }
  return value
}

func dataArray(_ object: [String: Any]) -> [[String: Any]] {
  object["data"] as? [[String: Any]] ?? []
}

func appID() -> String {
  let data = dataArray(api("GET", "/v1/apps?filter[bundleId]=\(bundleID)"))
  guard let first = data.first, let id = first["id"] as? String else {
    die("app \(bundleID) not found on this account")
  }
  return id
}

// The id and version string of the platform's editable version, or nil.
func findVersion(_ platform: String) -> (id: String, version: String)? {
  let path =
    "/v1/apps/\(appID())/appStoreVersions?filter[platform]=\(platform)"
    + "&filter[appStoreState]=PREPARE_FOR_SUBMISSION,DEVELOPER_REJECTED,REJECTED,METADATA_REJECTED,WAITING_FOR_REVIEW"
    + "&fields[appStoreVersions]=versionString"
  guard let first = dataArray(api("GET", path)).first,
    let id = first["id"] as? String,
    let attributes = first["attributes"] as? [String: Any],
    let version = attributes["versionString"] as? String
  else { return nil }
  return (id, version)
}

// The id of the version for a platform and string, created if absent.
// A platform's one editable version is renamed rather than duplicated.
func ensureVersion(_ platformName: String, _ version: String) -> String {
  let platform = apiPlatform(platformName)
  if let existing = findVersion(platform) {
    if existing.version == version { return existing.id }
    api(
      "PATCH", "/v1/appStoreVersions/\(existing.id)",
      body: [
        "data": [
          "type": "appStoreVersions", "id": existing.id,
          "attributes": ["versionString": version],
        ]
      ])
    return existing.id
  }
  let created = api(
    "POST", "/v1/appStoreVersions",
    body: [
      "data": [
        "type": "appStoreVersions",
        "attributes": ["platform": platform, "versionString": version],
        "relationships": ["app": ["data": ["type": "apps", "id": appID()]]],
      ]
    ])
  guard let data = created["data"] as? [String: Any], let id = data["id"] as? String else {
    die("could not create the version")
  }
  return id
}

func attachBuild(_ platformName: String, _ version: String, _ number: String) {
  let platform = apiPlatform(platformName)
  let versionID = ensureVersion(platformName, version)
  let path =
    "/v1/builds?filter[app]=\(appID())&filter[version]=\(number)&filter[preReleaseVersion.platform]=\(platform)&limit=1"
  guard let build = dataArray(api("GET", path)).first, let buildID = build["id"] as? String else {
    die("build \(number) for \(platformName) not found; has it finished processing?")
  }
  api(
    "PATCH", "/v1/appStoreVersions/\(versionID)/relationships/build",
    body: ["data": ["type": "builds", "id": buildID]])
  print("attached build \(number) to \(platformName) \(version)")
}

// The repository root, from this script's own location (Scripts/..),
// so Metadata/ is found however the tool is invoked.
let repository = URL(fileURLWithPath: #filePath)
  .resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()

// The submission details, defined in one place - Metadata/appstore.json
// - and the locale map inside it, locale to its fields.
let metadata: [String: Any] = {
  let url = repository.appendingPathComponent("Metadata/appstore.json")
  guard let data = try? Data(contentsOf: url),
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  else { die("could not read Metadata/appstore.json") }
  return json
}()
let localizations = metadata["localizations"] as? [String: Any] ?? [:]

// The existing localizations of a resource, locale to its id, so a
// push updates what is present and creates what is not.
func existingLocalizations(_ path: String) -> [String: String] {
  var map: [String: String] = [:]
  for entry in dataArray(api("GET", path)) {
    if let attributes = entry["attributes"] as? [String: Any],
      let locale = attributes["locale"] as? String, let id = entry["id"] as? String
    {
      map[locale] = id
    }
  }
  return map
}

// Create or update each locale's version localization from the JSON.
// The description is the platform's own; the rest is shared.
func pushMetadata(_ platformName: String, _ version: String) {
  let platform = apiPlatform(platformName)
  let versionID = ensureVersion(platformName, version)
  let hasLiveVersion = !dataArray(
    api(
      "GET",
      "/v1/apps/\(appID())/appStoreVersions?filter[platform]=\(platform)&filter[appStoreState]=READY_FOR_SALE&limit=1"
    )
  ).isEmpty
  // Copyright lives on the version itself, not on a localization.
  if let copyright = metadata["copyright"] as? String {
    api(
      "PATCH", "/v1/appStoreVersions/\(versionID)",
      body: [
        "data": [
          "type": "appStoreVersions", "id": versionID,
          "attributes": ["copyright": copyright],
        ]
      ])
    print("  copyright: \(copyright)")
  }
  let existing = existingLocalizations(
    "/v1/appStoreVersions/\(versionID)/appStoreVersionLocalizations?limit=50")
  for locale in localizations.keys.sorted() {
    let entry = localizations[locale] as? [String: Any] ?? [:]
    guard let description = (entry["description"] as? [String: Any])?[platformName] as? String
    else { continue }
    var attributes: [String: Any] = ["description": description]
    if hasLiveVersion,
      let whatsNew = (entry["whatsNew"] as? [String: Any])?[platformName] as? String
        ?? entry["whatsNew"] as? String
    {
      attributes["whatsNew"] = whatsNew
    }
    if let keywords = entry["keywords"] as? String { attributes["keywords"] = keywords }
    // Per platform, like the description: the Mac signs documents
    // and the iPhone does not yet, so one sentence cannot serve both.
    if let promo = (entry["promotionalText"] as? [String: Any])?[platformName] as? String {
      attributes["promotionalText"] = promo
    }
    if let support = metadata["supportUrl"] as? String { attributes["supportUrl"] = support }
    if let marketing = metadata["marketingUrl"] as? String {
      attributes["marketingUrl"] = marketing
    }
    if let id = existing[locale] {
      api(
        "PATCH", "/v1/appStoreVersionLocalizations/\(id)",
        body: [
          "data": [
            "type": "appStoreVersionLocalizations", "id": id,
            "attributes": attributes,
          ]
        ])
      print("  \(locale): updated")
    } else {
      attributes["locale"] = locale
      api(
        "POST", "/v1/appStoreVersionLocalizations",
        body: [
          "data": [
            "type": "appStoreVersionLocalizations", "attributes": attributes,
            "relationships": [
              "appStoreVersion": [
                "data": ["type": "appStoreVersions", "id": versionID]
              ]
            ],
          ]
        ])
      print("  \(locale): created")
    }
  }
}

// The app-level info record that carries name, subtitle and category.
func appInfoID() -> String {
  let infos = dataArray(api("GET", "/v1/apps/\(appID())/appInfos"))
  for info in infos {
    let state = (info["attributes"] as? [String: Any])?["state"] as? String
    if state == "PREPARE_FOR_SUBMISSION", let id = info["id"] as? String { return id }
  }
  guard let id = infos.first?["id"] as? String else { die("no app info record") }
  return id
}

// Sets the primary category and each locale's subtitle from the JSON.
// Both live on the app info record, not on a version.
func pushAppInfo() {
  let infoID = appInfoID()
  let category = metadata["primaryCategory"] as? String ?? "UTILITIES"
  api(
    "PATCH", "/v1/appInfos/\(infoID)",
    body: [
      "data": [
        "type": "appInfos", "id": infoID,
        "relationships": [
          "primaryCategory": [
            "data": ["type": "appCategories", "id": category]
          ]
        ],
      ]
    ])
  print("primary category: \(category)")
  let existing = existingLocalizations("/v1/appInfos/\(infoID)/appInfoLocalizations?limit=50")
  // The privacy policy URL lives here too, and is per locale: the
  // policy is published in each language at its own address. App
  // Store Connect asks for it on the app record rather than on a
  // version, and a submission without it is refused.
  for locale in localizations.keys.sorted() {
    let entry = localizations[locale] as? [String: Any] ?? [:]
    guard let subtitle = entry["subtitle"] as? String else { continue }
    var attributes: [String: Any] = ["subtitle": subtitle]
    if let policy = entry["privacyPolicyUrl"] as? String {
      attributes["privacyPolicyUrl"] = policy
    }
    if let id = existing[locale] {
      api(
        "PATCH", "/v1/appInfoLocalizations/\(id)",
        body: [
          "data": [
            "type": "appInfoLocalizations", "id": id,
            "attributes": attributes,
          ]
        ])
      print("  \(locale): subtitle and privacy policy updated")
    } else {
      attributes["locale"] = locale
      api(
        "POST", "/v1/appInfoLocalizations",
        body: [
          "data": [
            "type": "appInfoLocalizations",
            "attributes": attributes,
            "relationships": [
              "appInfo": [
                "data": ["type": "appInfos", "id": infoID]
              ]
            ],
          ]
        ])
      print("  \(locale): subtitle and privacy policy created")
    }
  }
}

// Sets the App Review contact and notes on a platform's version, from
// the JSON. No demo account: the app has no login.
func reviewContact(_ platformName: String, _ version: String) {
  let versionID = ensureVersion(platformName, version)
  let review = metadata["review"] as? [String: Any] ?? [:]
  var attributes: [String: Any] = [
    "contactFirstName": review["firstName"] ?? "",
    "contactLastName": review["lastName"] ?? "",
    "contactPhone": review["phone"] ?? "",
    "contactEmail": review["email"] ?? "",
    "demoAccountRequired": false,
  ]
  // Per platform, like the description: the two builds do not have the
  // same screens, and a note listing one that is not there is worse
  // than no note at all in front of a reviewer who cannot get past it.
  if let notes = (review["notes"] as? [String: Any])?[platformName] as? String {
    attributes["notes"] = notes
  }
  let existing =
    api(
      "GET", "/v1/appStoreVersions/\(versionID)/appStoreReviewDetail")["data"] as? [String: Any]
  if let id = existing?["id"] as? String {
    api(
      "PATCH", "/v1/appStoreReviewDetails/\(id)",
      body: [
        "data": ["type": "appStoreReviewDetails", "id": id, "attributes": attributes]
      ])
  } else {
    api(
      "POST", "/v1/appStoreReviewDetails",
      body: [
        "data": [
          "type": "appStoreReviewDetails", "attributes": attributes,
          "relationships": [
            "appStoreVersion": [
              "data": ["type": "appStoreVersions", "id": versionID]
            ]
          ],
        ]
      ])
  }
  print("review contact set for \(platformName) \(version)")
}

// Sets the age rating to 4+: every content category at its lowest and
// no unrestricted web access. The declaration is app-level, carried by
// the app info record and shared across platforms.
func pushAgeRating() {
  let declaration = api("GET", "/v1/appInfos/\(appInfoID())/ageRatingDeclaration")
  guard let id = (declaration["data"] as? [String: Any])?["id"] as? String
  else { die("no age rating declaration on the app info record") }
  let none = "NONE"
  let attributes: [String: Any] = [
    "alcoholTobaccoOrDrugUseOrReferences": none,
    "contests": none,
    "gamblingSimulated": none,
    "medicalOrTreatmentInformation": none,
    "profanityOrCrudeHumor": none,
    "sexualContentGraphicAndNudity": none,
    "sexualContentOrNudity": none,
    "horrorOrFearThemes": none,
    "matureOrSuggestiveThemes": none,
    "violenceCartoonOrFantasy": none,
    "violenceRealistic": none,
    "violenceRealisticProlongedGraphicOrSadistic": none,
    "gunsOrOtherWeapons": none,
    "healthOrWellnessTopics": false,
    "advertising": false,
    "gambling": false,
    "unrestrictedWebAccess": false,
    "ageAssurance": false,
    "lootBox": false,
    "messagingAndChat": false,
    "parentalControls": false,
    "userGeneratedContent": false,
  ]
  api(
    "PATCH", "/v1/ageRatingDeclarations/\(id)",
    body: [
      "data": ["type": "ageRatingDeclarations", "id": id, "attributes": attributes]
    ])
  print("age rating 4+ set")
}

// Marks the platform's uploaded build as using no non-exempt encryption
// - the standard exempt answer for an app that only authenticates and
// signs with the card, and does not itself ship an encryption product.
func pushExportCompliance(_ platformName: String) {
  let platform = apiPlatform(platformName)
  guard let versionInfo = findVersion(platform) else { die("no version for \(platformName)") }
  let response = api("GET", "/v1/appStoreVersions/\(versionInfo.id)?include=build")
  guard
    let build = (response["included"] as? [[String: Any]])?
      .first(where: { $0["type"] as? String == "builds" }), let buildID = build["id"] as? String
  else { die("no build attached to \(platformName) \(versionInfo.version)") }
  let usesNonExempt = metadata["usesNonExemptEncryption"] as? Bool ?? false
  // A build that shipped with ITSAppUsesNonExemptEncryption in its
  // Info.plist already carries the answer and cannot be overwritten.
  let current = (build["attributes"] as? [String: Any])?["usesNonExemptEncryption"] as? Bool
  if current == usesNonExempt {
    print("export compliance already exempt on \(platformName) build \(versionInfo.version)")
    return
  }
  api(
    "PATCH", "/v1/builds/\(buildID)",
    body: [
      "data": [
        "type": "builds", "id": buildID,
        "attributes": ["usesNonExemptEncryption": usesNonExempt],
      ]
    ])
  print("export compliance (exempt) set on \(platformName) build \(versionInfo.version)")
}

// Puts the app on the free tier in every territory: a price schedule
// whose base territory carries the zero price point, which the store
// equalizes across all territories.
// Sets the price schedule from the JSON: free, in every territory,
// priced from one base.
//
// The base is the territory Apple leaves alone when it adjusts prices
// elsewhere for tax or exchange rates, and it decides the currency the
// baseline is written in. It is named in the JSON rather than assumed,
// because the sensible base is the seller's own country and the
// default is not.
func pushPricing() {
  guard (metadata["pricing"] as? String) == "free" else {
    die(
      "only free pricing is supported; 'pricing' says "
        + "\(metadata["pricing"] ?? "nothing")")
  }
  let base = metadata["baseTerritory"] as? String ?? "USA"
  let app = appID()
  let points = dataArray(
    api(
      "GET", "/v1/apps/\(app)/appPricePoints?filter[territory]=\(base)&limit=200"))
  guard
    let freeID = points.first(where: {
      let price = ($0["attributes"] as? [String: Any])?["customerPrice"] as? String
      return price.flatMap(Double.init) == 0
    })?["id"] as? String
  else { die("no free price point for \(base)") }
  let temporary = "${free-price}"
  api(
    "POST", "/v1/appPriceSchedules",
    body: [
      "data": [
        "type": "appPriceSchedules",
        "relationships": [
          "app": ["data": ["type": "apps", "id": app]],
          "baseTerritory": ["data": ["type": "territories", "id": base]],
          "manualPrices": ["data": [["type": "appPrices", "id": temporary]]],
        ],
      ],
      "included": [
        [
          "type": "appPrices", "id": temporary,
          "relationships": [
            "appPricePoint": ["data": ["type": "appPricePoints", "id": freeID]],
            "territory": ["data": ["type": "territories", "id": base]],
          ],
        ]
      ],
    ])
  print("pricing: free, all territories, based on \(base)")
}

// Every review submission, and whether it is one.
//
// The state is not the answer: READY_FOR_REVIEW means a container could
// be sent, not that anything was. A submission is real when it carries
// a version and has a submitted date, which is what this prints.
//
// An empty container is left behind whenever a version is refused for
// review, and the API can create one but not remove it: DELETE is not
// an allowed operation on this resource, and an empty one is "not in a
// cancellable state" either. App Store Connect's own Submissions page
// deletes them, so those are named here rather than silently listed.
func submissions() {
  let all = dataArray(
    api(
      "GET", "/v1/reviewSubmissions?filter[app]=\(appID())&limit=50"))
  guard !all.isEmpty else {
    print("no review submissions")
    return
  }
  for entry in all {
    guard let id = entry["id"] as? String else { continue }
    let attributes = entry["attributes"] as? [String: Any] ?? [:]
    let submitted = attributes["submittedDate"] as? String
    let items = dataArray(api("GET", "/v1/reviewSubmissions/\(id)/items")).count
    let note =
      (items == 0 && submitted == nil)
      ? "   empty; delete it in App Store Connect"
      : ""
    print(
      String(
        format: "  %@ %@ versions=%d submitted=%@%@",
        (attributes["platform"] as? String ?? "-")
          .padding(toLength: 7, withPad: " ", startingAt: 0),
        (attributes["state"] as? String ?? "-")
          .padding(toLength: 20, withPad: " ", startingAt: 0),
        items,
        submitted ?? "-",
        note))
  }
}

// Submits a platform's version for App Review. This is the one step that
// leaves the account: it creates the review submission, adds the version
// as its item, and marks it submitted.
func submit(_ platformName: String, _ version: String) {
  let platform = apiPlatform(platformName)
  let versionID = ensureVersion(platformName, version)
  let app = appID()
  let open = dataArray(
    api(
      "GET",
      "/v1/reviewSubmissions?filter[app]=\(app)"
        + "&filter[platform]=\(platform)&filter[state]=READY_FOR_REVIEW,WAITING_FOR_REVIEW"))
  let submissionID: String
  if let id = open.first?["id"] as? String {
    submissionID = id
  } else {
    let created = api(
      "POST", "/v1/reviewSubmissions",
      body: [
        "data": [
          "type": "reviewSubmissions",
          "attributes": ["platform": platform],
          "relationships": ["app": ["data": ["type": "apps", "id": app]]],
        ]
      ])
    guard let id = (created["data"] as? [String: Any])?["id"] as? String
    else { die("could not create a review submission") }
    submissionID = id
  }
  api(
    "POST", "/v1/reviewSubmissionItems",
    body: [
      "data": [
        "type": "reviewSubmissionItems",
        "relationships": [
          "reviewSubmission": ["data": ["type": "reviewSubmissions", "id": submissionID]],
          "appStoreVersion": ["data": ["type": "appStoreVersions", "id": versionID]],
        ],
      ]
    ])
  api(
    "PATCH", "/v1/reviewSubmissions/\(submissionID)",
    body: [
      "data": [
        "type": "reviewSubmissions", "id": submissionID,
        "attributes": ["submitted": true],
      ]
    ])
  print("submitted \(platformName) \(version) for review")
}

// PUTs one chunk to a reserved upload URL. These are presigned, so they
// carry their own auth in the headers the reservation handed back and
// must not get the API bearer token.
func putChunk(_ operation: [String: Any], _ data: Data) {
  guard let urlString = operation["url"] as? String, let url = URL(string: urlString),
    let offset = operation["offset"] as? Int, let length = operation["length"] as? Int
  else { die("malformed upload operation") }
  var request = URLRequest(url: url)
  request.httpMethod = operation["method"] as? String ?? "PUT"
  for header in operation["requestHeaders"] as? [[String: Any]] ?? [] {
    if let name = header["name"] as? String, let value = header["value"] as? String {
      request.setValue(value, forHTTPHeaderField: name)
    }
  }
  request.httpBody = data.subdata(in: offset..<(offset + length))
  let semaphore = DispatchSemaphore(value: 0)
  var status = 0
  URLSession.shared.dataTask(with: request) { _, response, _ in
    status = (response as? HTTPURLResponse)?.statusCode ?? 0
    semaphore.signal()
  }.resume()
  semaphore.wait()
  guard (200..<300).contains(status) else { die("HTTP \(status) uploading a screenshot chunk") }
}

// The screenshot set for a version localization and display type, its
// existing shots cleared so a re-run replaces rather than appends.
func screenshotSet(localizationID: String, displayType: String) -> String {
  let sets = dataArray(
    api(
      "GET", "/v1/appStoreVersionLocalizations/\(localizationID)/appScreenshotSets"))
  let setID: String
  if let match = sets.first(where: {
    ($0["attributes"] as? [String: Any])?["screenshotDisplayType"] as? String == displayType
  }), let id = match["id"] as? String {
    setID = id
    for shot in dataArray(api("GET", "/v1/appScreenshotSets/\(setID)/appScreenshots")) {
      if let id = shot["id"] as? String { api("DELETE", "/v1/appScreenshots/\(id)") }
    }
  } else {
    let created = api(
      "POST", "/v1/appScreenshotSets",
      body: [
        "data": [
          "type": "appScreenshotSets",
          "attributes": ["screenshotDisplayType": displayType],
          "relationships": [
            "appStoreVersionLocalization": [
              "data": [
                "type": "appStoreVersionLocalizations",
                "id": localizationID,
              ]
            ]
          ],
        ]
      ])
    guard let id = (created["data"] as? [String: Any])?["id"] as? String
    else { die("no screenshot set id") }
    setID = id
  }
  return setID
}

// Reserves, uploads and commits one screenshot into a set.
func uploadScreenshot(setID: String, file: URL) {
  guard let data = try? Data(contentsOf: file) else { die("cannot read \(file.path)") }
  let reservation = api(
    "POST", "/v1/appScreenshots",
    body: [
      "data": [
        "type": "appScreenshots",
        "attributes": ["fileName": file.lastPathComponent, "fileSize": data.count],
        "relationships": [
          "appScreenshotSet": [
            "data": ["type": "appScreenshotSets", "id": setID]
          ]
        ],
      ]
    ])
  guard let reserved = reservation["data"] as? [String: Any], let id = reserved["id"] as? String,
    let operations = (reserved["attributes"] as? [String: Any])?["uploadOperations"]
      as? [[String: Any]]
  else { die("no upload operations for \(file.lastPathComponent)") }
  for operation in operations { putChunk(operation, data) }
  let checksum = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
  api(
    "PATCH", "/v1/appScreenshots/\(id)",
    body: [
      "data": [
        "type": "appScreenshots", "id": id,
        "attributes": ["uploaded": true, "sourceFileChecksum": checksum],
      ]
    ])
  print("    \(file.lastPathComponent)")
}

// Whether a display type belongs to a platform.
//
// The locale folders hold every platform's shots side by side, and a
// version takes only its own: offering a Mac version an iPhone set is
// refused with "Display Type Not Allowed", which aborted the run and
// left the locales after it with nothing.
func platform(_ platformName: String, shows folderName: String) -> Bool {
  switch platformName {
  case "macos":
    folderName.hasPrefix("APP_DESKTOP")
  default:
    folderName.hasPrefix("APP_IPHONE") || folderName.hasPrefix("APP_IPAD")
  }
}

// Uploads every PNG under Metadata/screenshots/<locale>/<DISPLAY_TYPE>/
// for a platform's version, one screenshot set per display type.
func pushScreenshots(_ platformName: String, _ version: String) {
  print("Uploading App Store version screenshots; TestFlight invitations use the latest approved")
  print("Ready for Distribution version. Draft screenshots do not update TestFlight invitations.")
  let versionID = ensureVersion(platformName, version)
  let versionLocalizations = existingLocalizations(
    "/v1/appStoreVersions/\(versionID)/appStoreVersionLocalizations?limit=50")
  let root = repository.appendingPathComponent("Metadata/screenshots")
  let fileManager = FileManager.default
  for (locale, localizationID) in versionLocalizations.sorted(by: { $0.key < $1.key }) {
    let localeDir = root.appendingPathComponent(locale)
    guard
      let displayDirs = try? fileManager.contentsOfDirectory(
        at: localeDir, includingPropertiesForKeys: nil)
    else { continue }
    print("  \(locale):")
    for displayDir in displayDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
      let displayType = displayDir.lastPathComponent
      guard platform(platformName, shows: displayType) else { continue }
      let shots =
        ((try? fileManager.contentsOfDirectory(
          at: displayDir, includingPropertiesForKeys: nil)) ?? [])
        .filter { $0.pathExtension.lowercased() == "png" }
        .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
      guard !shots.isEmpty else { continue }
      print("    [\(displayType)]")
      let setID = screenshotSet(localizationID: localizationID, displayType: displayType)
      for shot in shots { uploadScreenshot(setID: setID, file: shot) }
    }
  }
}

// The platform's recent builds with their TestFlight readiness: a build
// is testable once it processes to VALID, and reaches external testers
// once its beta review is APPROVED. Internal testers need only VALID.
func builds(_ platformName: String) {
  let platform = apiPlatform(platformName)
  let path =
    "/v1/builds?filter[app]=\(appID())&filter[preReleaseVersion.platform]=\(platform)"
    + "&sort=-uploadedDate&limit=10&include=preReleaseVersion,betaAppReviewSubmission"
    + "&fields[builds]=version,processingState,expired,preReleaseVersion,betaAppReviewSubmission"
    + "&fields[preReleaseVersions]=version&fields[betaAppReviewSubmissions]=betaReviewState"
  let response = api("GET", path)
  var included: [String: [String: Any]] = [:]
  for entry in response["included"] as? [[String: Any]] ?? [] {
    if let type = entry["type"] as? String, let id = entry["id"] as? String {
      included["\(type)/\(id)"] = entry["attributes"] as? [String: Any]
    }
  }
  func related(_ build: [String: Any], _ name: String, _ type: String) -> [String: Any]? {
    let relationship = (build["relationships"] as? [String: Any])?[name] as? [String: Any]
    guard let id = (relationship?["data"] as? [String: Any])?["id"] as? String else { return nil }
    return included["\(type)/\(id)"]
  }
  for build in dataArray(response) {
    let attributes = build["attributes"] as? [String: Any] ?? [:]
    let marketing =
      related(build, "preReleaseVersion", "preReleaseVersions")?["version"]
      as? String ?? "-"
    let review =
      related(build, "betaAppReviewSubmission", "betaAppReviewSubmissions")?[
        "betaReviewState"] as? String ?? "none"
    let expired = (attributes["expired"] as? Bool ?? false) ? " expired" : ""
    print(
      String(
        format: "  %@ build %@ %@ beta=%@%@",
        marketing.padding(toLength: 10, withPad: " ", startingAt: 0),
        (attributes["version"] as? String ?? "").padding(toLength: 5, withPad: " ", startingAt: 0),
        (attributes["processingState"] as? String ?? "").padding(
          toLength: 10, withPad: " ", startingAt: 0),
        review, expired))
  }
}

// Distributes the named candidate, or the newest build when no ID is given.
// External testers need beta review; internal testers need only a valid build.
// App Store build attachment is a separate command.
func distribute(_ platformName: String, _ groupName: String, _ candidateID: String? = nil) {
  let platform = apiPlatform(platformName)
  let buildsPath =
    "/v1/builds?filter[app]=\(appID())"
    + "&filter[preReleaseVersion.platform]=\(platform)&sort=-uploadedDate&limit=100"
  let candidates = dataArray(api("GET", buildsPath))
  let selected = candidateID.map { id in candidates.first { $0["id"] as? String == id } }
    ?? candidates.first
  guard let build = selected, let buildID = build["id"] as? String
  else { die("no \(platformName) build to distribute") }
  let attributes = build["attributes"] as? [String: Any] ?? [:]
  guard attributes["processingState"] as? String == "VALID",
    attributes["expired"] as? Bool != true
  else { die("candidate must finish processing and must not be expired") }
  let groups = dataArray(api("GET", "/v1/apps/\(appID())/betaGroups?limit=50"))
  guard
    let group = groups.first(where: {
      ($0["attributes"] as? [String: Any])?["name"] as? String == groupName
    }), let groupID = group["id"] as? String
  else { die("no beta group named '\(groupName)'") }
  api(
    "POST", "/v1/betaGroups/\(groupID)/relationships/builds",
    body: [
      "data": [["type": "builds", "id": buildID]]
    ])
  print("added \(platformName) build to group '\(groupName)'")
  if (group["attributes"] as? [String: Any])?["isInternalGroup"] as? Bool == true {
    return
  }
  let review = api("GET", "/v1/builds/\(buildID)/betaAppReviewSubmission")["data"] as? [String: Any]
  if review == nil {
    api(
      "POST", "/v1/betaAppReviewSubmissions",
      body: [
        "data": [
          "type": "betaAppReviewSubmissions",
          "relationships": ["build": ["data": ["type": "builds", "id": buildID]]],
        ]
      ])
    print("submitted \(platformName) build for beta review")
  } else {
    print("beta review already exists for the \(platformName) build")
  }
}

// Creates a beta tester in a beta group. Joining an external group is
// what makes App Store Connect send the TestFlight invitation email, so
// this is the whole "invite a new tester" flow; `invite` merely resends.
func addTester(_ email: String, _ groupName: String) {
  let groups = dataArray(api("GET", "/v1/apps/\(appID())/betaGroups?limit=50"))
  guard
    let groupID = groups.first(where: {
      ($0["attributes"] as? [String: Any])?["name"] as? String == groupName
    })?["id"] as? String
  else { die("no beta group named '\(groupName)'") }
  api(
    "POST", "/v1/betaTesters",
    body: [
      "data": [
        "type": "betaTesters",
        "attributes": ["email": email],
        "relationships": [
          "betaGroups": ["data": [["type": "betaGroups", "id": groupID]]]
        ],
      ]
    ])
  print("added \(email) to group '\(groupName)'")
}

// Removes a beta tester from a beta group.
func removeTester(_ email: String, _ groupName: String) {
  let groups = dataArray(api("GET", "/v1/apps/\(appID())/betaGroups?limit=50"))
  guard
    let groupID = groups.first(where: {
      ($0["attributes"] as? [String: Any])?["name"] as? String == groupName
    })?["id"] as? String
  else { die("no beta group named '\(groupName)'") }
  let testers = dataArray(api("GET", "/v1/betaTesters?filter[email]=\(email)"))
  guard let testerID = testers.first?["id"] as? String else {
    die("no beta tester with email \(email)")
  }
  api(
    "DELETE", "/v1/betaGroups/\(groupID)/relationships/betaTesters",
    body: [
      "data": [["type": "betaTesters", "id": testerID]]
    ])
  print("removed \(email) from group '\(groupName)'")
}

// Sends a TestFlight invitation email to an existing beta tester. The
// tester must already be on the app (in a group or assigned a build);
// this is the "resend invite" the App Store Connect UI offers.
func invite(_ email: String) {
  let testers = dataArray(api("GET", "/v1/betaTesters?filter[email]=\(email)"))
  guard let testerID = testers.first?["id"] as? String else {
    die("no beta tester with email \(email); add them to a group first")
  }
  api(
    "POST", "/v1/betaTesterInvitations",
    body: [
      "data": [
        "type": "betaTesterInvitations",
        "relationships": [
          "app": ["data": ["type": "apps", "id": appID()]],
          "betaTester": ["data": ["type": "betaTesters", "id": testerID]],
        ],
      ]
    ])
  print("TestFlight invite sent to \(email)")
}

func state() {
  let path =
    "/v1/apps/\(appID())/appStoreVersions?fields[appStoreVersions]="
    + "versionString,platform,appStoreState,build&include=build"
    + "&fields[builds]=version&limit=50"
  let response = api("GET", path)
  var builds: [String: String] = [:]
  for entry in (response["included"] as? [[String: Any]] ?? [])
  where entry["type"] as? String == "builds" {
    if let id = entry["id"] as? String, let attributes = entry["attributes"] as? [String: Any],
      let version = attributes["version"] as? String
    {
      builds[id] = version
    }
  }
  for version in dataArray(response) {
    let attributes = version["attributes"] as? [String: Any] ?? [:]
    let relationship = (version["relationships"] as? [String: Any])?["build"] as? [String: Any]
    let buildID = (relationship?["data"] as? [String: Any])?["id"] as? String
    let build = buildID.flatMap { builds[$0] } ?? "-"
    print(
      String(
        format: "  %@ %@ %@ build=%@",
        (attributes["platform"] as? String ?? "").padding(toLength: 7, withPad: " ", startingAt: 0),
        (attributes["versionString"] as? String ?? "").padding(
          toLength: 10, withPad: " ", startingAt: 0),
        (attributes["appStoreState"] as? String ?? "").padding(
          toLength: 24, withPad: " ", startingAt: 0),
        build))
  }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.isEmpty || ["help", "--help", "-h"].contains(arguments[0]) {
  printReleaseManagerUsage()
  exit(0)
}
guard let command = arguments.first else { die("a command is required; see the header") }
let rest = Array(arguments.dropFirst())

switch (command, rest.count) {
case ("install-devices", _):
  installDevices(rest)
case ("install-macos", _):
  installMacOS(rest)
case ("purge-stale-registrations", _):
  installPurgeStaleRegistrationsCommand(rest)
case ("install-ios", _):
  installIOSCommand(rest)
case ("install-nfc-timing", _):
  installNFCTiming(rest)
case ("install-pkcs11", _):
  installPKCS11(rest)
case ("stamp", _):
  releaseStamp(rest)
case ("candidate", _):
  releaseCandidate(rest)
case ("inspect-archive", 1):
  inspectReleaseArchive(URL(fileURLWithPath: rest[0]))
case ("capture-screenshots", _):
  releaseCaptureScreenshots(rest)
case ("get", 1):
  printJSON(api("GET", rest[0]))
case ("api", 2):
  printJSON(api(rest[0].uppercased(), rest[1]))
case ("api", 3):
  printJSON(api(rest[0].uppercased(), rest[1], body: readBody(rest[2])))
case ("app-id", 0): print(appID())
case ("state", 0): state()
case ("builds", 1): builds(rest[0])
case ("distribute", 1): distribute(rest[0], "Beta")
case ("distribute", 2): distribute(rest[0], rest[1])
case ("distribute", 3): distribute(rest[0], rest[1], rest[2])
case ("add-tester", 1): addTester(rest[0], "Beta")
case ("add-tester", 2): addTester(rest[0], rest[1])
case ("remove-tester", 1): removeTester(rest[0], "Beta")
case ("remove-tester", 2): removeTester(rest[0], rest[1])
case ("invite", 1): invite(rest[0])
case ("ensure-version", 2): print(ensureVersion(rest[0], rest[1]))
case ("attach-build", 3): attachBuild(rest[0], rest[1], rest[2])
case ("metadata", 2): pushMetadata(rest[0], rest[1])
case ("app-info", 0): pushAppInfo()
case ("review-contact", 2): reviewContact(rest[0], rest[1])
case ("screenshots", 2): pushScreenshots(rest[0], rest[1])
case ("age-rating", 0): pushAgeRating()
case ("export-compliance", 1): pushExportCompliance(rest[0])
case ("pricing", 0): pushPricing()
case ("submissions", 0): submissions()
case ("submit", 2): submit(rest[0], rest[1])
default: die("unknown command or wrong arguments: '\(command)'; see the header")
}
