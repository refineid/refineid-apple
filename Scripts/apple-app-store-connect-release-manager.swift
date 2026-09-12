#!/usr/bin/env swift  // Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.  //  // Drive the complete Apple release lifecycle in the language this project  // is written in and with no shell release entry points.  //  // Local commands archive, inspect, export, and optionally upload a candidate.  // The remaining web-UI steps are JSON-over-HTTP calls, and doing them by hand
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
// Usage:
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
//   apple-app-store-connect-release-manager.swift age-rating
//   apple-app-store-connect-release-manager.swift export-compliance <ios|macos>
//   apple-app-store-connect-release-manager.swift pricing
//   apple-app-store-connect-release-manager.swift submissions
//   apple-app-store-connect-release-manager.swift submit <ios|macos> <versionString>

import CryptoKit
import Foundation

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
      // The first full version carries the remote card (owner decision
      // 2026-09-10), so a macOS candidate carries the RAPP extension,
      // the local-network declarations, and the server entitlement.
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
    #"refineid-token-extension\.log|Uniffi callback interface .*handle missing in uniffiFree|\[(persistent-relay|persistent-token)\]|^(sign|session|discovery|mintFromPrime|createToken|supports|beginAuth|unseal|reader|prime): |^--(diagnostics|trace|reset-card-state|set-can|forget-can|set-pin1|prime)$"#
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
    // The client side stays in a gated candidate for timestamps and
    // revocation fetches; the server side exists only for the remote
    // card's relay listener, so it ships exactly when the RAPP
    // extension does.
    let appEntitlements: Set<String> = Set([
      "com.apple.security.app-sandbox",
      "com.apple.security.application-groups",
      "com.apple.security.files.user-selected.read-write",
      "com.apple.security.network.client",
      "com.apple.security.smartcard",
    ]).union(layout.hasRapp ? ["com.apple.security.network.server"] : [])
    var rules: [(bundle: URL, allowed: Set<String>, required: Set<String>)] = [
      (
        layout.app,
        signingEntitlements.union(appEntitlements),
        appEntitlements
      ),
      (
        layout.tokenBundle,
        signingEntitlements.union([
          "com.apple.security.app-sandbox",
          "com.apple.security.application-groups",
          "com.apple.security.smartcard",
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
            "com.apple.security.network.server",
          ]),
          [
            "com.apple.security.app-sandbox",
            "com.apple.security.application-groups",
            "com.apple.security.network.client",
            "com.apple.security.network.server",
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
    entitlementRules = bundles.map {
      ($0, allowed, ["keychain-access-groups"])
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
      for entitlement in [
        "com.apple.security.network.client",
        "com.apple.security.network.server",
      ] {
        guard appEntitlements[entitlement] as? Bool == true else {
          releaseFail("\(layout.app.path): missing RAPP entitlement \(entitlement)")
        }
        guard rappEntitlements[entitlement] as? Bool == true else {
          releaseFail(
            "\(layout.rappBundle.path): missing RAPP entitlement \(entitlement)"
          )
        }
      }
      guard rappEntitlements["com.apple.security.smartcard"] == nil else {
        releaseFail("\(layout.rappBundle.path): RAPP requester carries direct-card access")
      }
      releaseNote("RAPP and direct-reader entitlements are separated")
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
      bonjourServices.contains("_refineid-rly._tcp")
    else {
      releaseFail("NSBonjourServices does not declare _refineid-rly._tcp")
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
        == "fi.refineid.refineid.rapp-token",
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
  let marketingVersion = String(format: "%02d.%d.%d", year % 100, month, day)
  let buildNumber = hour * 10 + minute / 10
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
        "-allowProvisioningUpdates",
        "-quiet",
      ],
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
  }
  print("Candidate complete: \(marketingVersion) (\(buildNumber)), commit \(commit)")
}

private func releaseCaptureScreenshots(_ arguments: [String]) {
  let script = releaseRepositoryRoot.appendingPathComponent("Scripts/store-screenshot-ios.sh")
  guard releaseFileManager.fileExists(atPath: script.path) else {
    releaseFail("screenshot script not found at \(script.path)")
  }
  print("Capturing iOS store screenshots...")
  releaseRun("/bin/bash", [script.path] + arguments, currentDirectory: releaseRepositoryRoot)
}

private func printReleaseManagerUsage() {
  print(
    """
    Usage: Scripts/apple-app-store-connect-release-manager.swift <command> [arguments]

    Local release commands:
      candidate [ios|macos|all] [--upload]
          Archive, inspect, and export a clean-tree candidate. Upload is opt-in.
      inspect-archive <path-to-xcarchive>
          Apply every reviewed archive gate without uploading or changing App Store state.
      capture-screenshots [options]
          Capture localized App Store screenshots on simulator (e.g. --all, --locale fi).

    App Store Connect commands:
      get, api, app-id, state, builds, distribute, add-tester, invite
      ensure-version, attach-build, metadata, app-info, review-contact
      screenshots, age-rating, export-compliance, pricing, submissions, submit
    """
  )
}

private let releaseManagerArguments = Array(CommandLine.arguments.dropFirst())
if releaseManagerArguments.isEmpty
  || ["help", "--help", "-h"].contains(releaseManagerArguments[0])
{
  printReleaseManagerUsage()
  exit(0)
}
switch releaseManagerArguments[0] {
case "candidate":
  releaseCandidate(Array(releaseManagerArguments.dropFirst()))
  exit(0)
case "inspect-archive":
  guard releaseManagerArguments.count == 2 else {
    releaseFail("usage: inspect-archive <path-to-xcarchive>")
  }
  inspectReleaseArchive(URL(fileURLWithPath: releaseManagerArguments[1]))
  exit(0)
case "capture-screenshots":
  releaseCaptureScreenshots(Array(releaseManagerArguments.dropFirst()))
  exit(0)
default:
  break
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
  let versionID = ensureVersion(platformName, version)
  let path = "/v1/builds?filter[app]=\(appID())&filter[version]=\(number)&limit=1"
  guard let build = dataArray(api("GET", path)).first, let buildID = build["id"] as? String else {
    die("build \(number) not found; has it finished processing?")
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
  _ = apiPlatform(platformName)
  let versionID = ensureVersion(platformName, version)
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

// Distributes a platform's newest build to a beta group and submits it
// for beta app review. An external group only shows a build to its
// testers once that review is approved; internal groups need no review.
func distribute(_ platformName: String, _ groupName: String) {
  let platform = apiPlatform(platformName)
  let buildsPath =
    "/v1/builds?filter[app]=\(appID())"
    + "&filter[preReleaseVersion.platform]=\(platform)&sort=-uploadedDate&limit=1"
  guard let build = dataArray(api("GET", buildsPath)).first, let buildID = build["id"] as? String
  else { die("no \(platformName) build to distribute") }
  let groups = dataArray(api("GET", "/v1/apps/\(appID())/betaGroups?limit=50"))
  guard
    let groupID = groups.first(where: {
      ($0["attributes"] as? [String: Any])?["name"] as? String == groupName
    })?["id"] as? String
  else { die("no beta group named '\(groupName)'") }
  api(
    "POST", "/v1/betaGroups/\(groupID)/relationships/builds",
    body: [
      "data": [["type": "builds", "id": buildID]]
    ])
  print("added \(platformName) build to group '\(groupName)'")
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
guard let command = arguments.first else { die("a command is required; see the header") }
let rest = Array(arguments.dropFirst())

switch (command, rest.count) {
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
case ("add-tester", 1): addTester(rest[0], "Beta")
case ("add-tester", 2): addTester(rest[0], rest[1])
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
