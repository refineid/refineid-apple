// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

/// The remote-card gate, pinned.
///
/// The macOS app is the local card and reader; the remote card (RAPP:
/// pairing, the phone's card, the pairing vault) comes into a build only
/// through `REFINEID_REMOTE_CARD`, which `Config/Features.xcconfig` sets
/// for every iOS configuration and leaves empty for macOS. A source that
/// names one of those types on a line the macOS build compiles, without
/// the flag over it, fails here: wrap it in the flag, or add the file to
/// the reviewed list below with the reason it is shared.
///
/// The list is empty now that the identity row's phone cases follow the
/// flag; it stays so a shared file can be named with its reason rather
/// than loosening the rule.
@Suite
internal struct RappGatingContractTests {
  /// One conditional-compilation branch a line sits under.
  private struct Branch {
    /// The condition as written.
    var condition: String
    /// Whether that condition denies the macOS build: an iOS-only branch.
    var excludesMacOS: Bool
    /// Whether this is the branch after an `#else`.
    var inElse = false

    /// Whether the macOS build leaves this branch out.
    var leavesMacOSOut: Bool { inElse ? !excludesMacOS : excludesMacOS }

    /// Whether the remote card is switched on here.
    var enablesRemoteCard: Bool { !inElse && condition.contains("REFINEID_REMOTE_CARD") }
  }

  private static var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  /// Shared sources that name the phone without being RAPP code.
  ///
  /// Empty: every source in `Sources/App` that names the remote card now
  /// compiles only where the flag is on. A file added here needs the
  /// reason it is shared, and the reason has to hold.
  private static let shared: [String: String] = [:]

  /// The remote card's own names: the engine's, the pairing's, the
  /// vault's, and the phone's card.
  private static let pattern =
    #"\b(Rapp\w*|Noise\w*|Vault\w*|Pairing\w*|Paired\w*|PhoneCard\w*|vault)\b"#

  /// The application's own sources, relative to the repository root.
  private static func appSources() throws -> [String] {
    let directory = root.appending(path: "Sources/App")
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    return names.filter { $0.hasSuffix(".swift") }.map { "Sources/App/" + $0 }.sorted()
  }

  /// The first name the line uses, if it uses one.
  private static func firstMarker(in line: String) -> String? {
    guard let range = line.range(of: pattern, options: .regularExpression) else {
      return nil
    }
    return String(line[range])
  }

  /// The branches after an `#if`, `#elseif`, `#else` or `#endif`.
  private static func applying(_ directive: String, to branches: [Branch]) -> [Branch] {
    var updated = branches
    if directive.hasPrefix("#if ") {
      updated.append(Branch(condition: directive, excludesMacOS: excludesMacOS(directive)))
    } else if directive.hasPrefix("#elseif "), !updated.isEmpty {
      updated[updated.count - 1] = Branch(
        condition: directive, excludesMacOS: excludesMacOS(directive))
    } else if directive == "#else", !updated.isEmpty {
      updated[updated.count - 1].inElse = true
    } else if directive == "#endif", !updated.isEmpty {
      updated.removeLast()
    }
    return updated
  }

  /// Whether the condition keeps the macOS build away.
  private static func excludesMacOS(_ condition: String) -> Bool {
    condition.contains("os(iOS)") && !condition.contains("os(macOS)")
  }

  /// The text without comments or string contents, so prose about pairing
  /// does not count and no name can hide in a comment.
  private static func code(_ text: String) -> String {
    let characters = Array(text)
    var result = ""
    var index = 0
    while index < characters.count {
      if characters[index] == "\"" {
        index = skippingString(characters, from: index)
        continue
      }
      if characters[index] == "/", index + 1 < characters.count {
        if characters[index + 1] == "/" {
          index = skippingLineComment(characters, from: index)
          continue
        }
        if characters[index + 1] == "*" {
          let comment = skippingBlockComment(characters, from: index)
          result += comment.blankLines
          index = comment.end
          continue
        }
      }
      result.append(characters[index])
      index += 1
    }
    return result
  }

  /// Where a `/* */` comment ends, and the line breaks it spans.
  private static func skippingBlockComment(
    _ characters: [Character], from start: Int
  ) -> (end: Int, blankLines: String) {
    var index = start + 2
    var blankLines = ""
    while index + 1 < characters.count {
      if characters[index] == "*", characters[index + 1] == "/" {
        return (index + 2, blankLines)
      }
      if characters[index] == "\n" { blankLines += "\n" }
      index += 1
    }
    return (characters.count, blankLines)
  }

  /// Where the line break ending a `//` comment is.
  private static func skippingLineComment(_ characters: [Character], from start: Int) -> Int {
    var index = start
    while index < characters.count, characters[index] != "\n" {
      index += 1
    }
    return index
  }

  /// Where a string literal ends, its contents dropped.
  private static func skippingString(_ characters: [Character], from start: Int) -> Int {
    var index = start + 1
    while index < characters.count {
      if characters[index] == "\\" {
        index += 2
        continue
      }
      if characters[index] == "\"" {
        return index + 1
      }
      index += 1
    }
    return index
  }

  /// The first name on each line the macOS build compiles without the flag
  /// over it, as `file:line: name`.
  private static func ungated(_ file: String) throws -> [String] {
    let text = try String(contentsOf: root.appending(path: file), encoding: .utf8)
    var branches: [Branch] = []
    var found: [String] = []
    for (offset, line) in code(text).split(separator: "\n", omittingEmptySubsequences: false)
      .enumerated()
    {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("#") {
        branches = applying(trimmed, to: branches)
        continue
      }
      guard !branches.contains(where: \.leavesMacOSOut) else { continue }
      guard !branches.contains(where: \.enablesRemoteCard) else { continue }
      guard let name = firstMarker(in: String(line)) else { continue }
      found.append("\(file):\(offset + 1): \(name)")
    }
    return found
  }

  /// Every remote-card name the macOS build compiles is behind the flag.
  @Test
  internal func remoteCardCodeIsGated() throws {
    var violations: [String] = []
    for file in try Self.appSources() where Self.shared[file] == nil {
      violations.append(contentsOf: try Self.ungated(file))
    }
    #expect(
      violations.isEmpty,
      """
      These lines reach the macOS build without REFINEID_REMOTE_CARD. \
      Wrap each in the flag, or, when the file is shared local-card code, \
      add it to RappGatingContractTests.shared with its reason:
      \(violations.joined(separator: "\n"))
      """)
  }

  /// The reviewed list names files that still exist and still need it.
  @Test
  internal func sharedListIsCurrent() throws {
    let sources = Set(try Self.appSources())
    for (file, reason) in Self.shared.sorted(by: { $0.key < $1.key }) {
      #expect(sources.contains(file), "\(file) is listed as shared but no longer exists")
      #expect(!reason.isEmpty, "\(file) needs the reason it is shared")
      #expect(
        try !Self.ungated(file).isEmpty,
        "\(file) is listed as shared but names no remote-card type, so drop the entry")
    }
  }
}
