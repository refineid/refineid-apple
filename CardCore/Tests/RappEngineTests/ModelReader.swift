// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import RappEngine

/// Indentation levels of the block-style model document.
private let modelIndentSection = 2
private let modelIndentRule = 4
private let modelIndentRuleField = 6

/// A `key: value` line splits into exactly this many parts.
private let keyValueParts = 2
/// The `- ` that opens a rule.
private let ruleMarkerLength = 2

/// A deliberately small reader for the block-style subset the model uses.
internal struct ModelReader {
  // MARK: Nested Types

  fileprivate struct Parser {
    fileprivate var version = ""
    fileprivate var guardNames: Set<String> = []
    fileprivate var guardStatements: [String: String] = [:]
    fileprivate var actionNames: Set<String> = []
    fileprivate var constants: [String: UInt64] = [:]
    fileprivate var rules: [String: [ParsedRule]] = ["pairing": [], "session": [], "operation": []]
    fileprivate var states: [String: [String]] = ["pairing": [], "session": [], "operation": []]
    fileprivate var section = ""
    fileprivate var inTransitions = false
    fileprivate var inStates = false
    fileprivate var current: ParsedRule?

    fileprivate mutating func flush() {
      if let rule = current, !section.isEmpty, rules[section] != nil {
        rules[section]?.append(rule)
      }
      current = nil
    }

    fileprivate mutating func feedSection(_ body: String) {
      flush()
      let key = body.trimmingCharacters(in: .whitespaces).split(separator: ":", maxSplits: 1)[0]
      inTransitions = String(key) == "transitions"
      inStates = String(key) == "states"
      if !inTransitions {
        if section == "guards" {
          guardNames.insert(String(key))
          guardStatements[String(key)] = ModelReader.value(of: body)
        }
        if section == "actions" { actionNames.insert(String(key)) }
        if section == "constants", let value = UInt64(ModelReader.value(of: body)) {
          constants[String(key)] = value
        }
      }
    }

    fileprivate mutating func feedLine(_ rawLine: Substring) {
      let line = String(rawLine)
      if line.trimmingCharacters(in: .whitespaces).hasPrefix("#") { return }
      let body = ModelReader.stripComment(line)
      if body.trimmingCharacters(in: .whitespaces).isEmpty { return }
      let indent = body.prefix { $0 == " " }.count

      if indent == 0 {
        flush()
        inTransitions = false
        inStates = false
        let name = body.split(separator: ":", maxSplits: 1)[0]
        section = String(name)
        if section == "document_version" {
          let quoted = CharacterSet(charactersIn: "\"")
          version = ModelReader.value(of: body).trimmingCharacters(in: quoted)
        }
        return
      }

      if indent == modelIndentSection {
        feedSection(body)
        return
      }

      let trimmed = body.trimmingCharacters(in: .whitespaces)
      if inStates, indent == modelIndentRule, trimmed.hasPrefix("- "), states[section] != nil {
        states[section]?.append(String(trimmed.dropFirst(ruleMarkerLength)))
        return
      }
      guard inTransitions else { return }
      if indent == modelIndentRule, trimmed.hasPrefix("- ") {
        flush()
        var rule = ParsedRule()
        ModelReader.assign(String(trimmed.dropFirst(ruleMarkerLength)), into: &rule)
        current = rule
      } else if indent >= modelIndentRuleField, var rule = current {
        ModelReader.assign(trimmed, into: &rule)
        current = rule
      }
    }
  }

  internal let documentVersion: String
  internal let guardNames: Set<String>
  /// Each guard's prose definition, by name.
  internal let guardStatements: [String: String]
  internal let actionNames: Set<String>
  /// The model's named numbers, by name.
  internal let constants: [String: UInt64]
  internal let rules: [String: [ParsedRule]]
  /// The states each machine declares, in model order.
  internal let states: [String: [String]]

  internal init(text: String) {
    var parser = Parser()
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
      parser.feedLine(rawLine)
    }
    parser.flush()

    self.documentVersion = parser.version
    self.guardNames = parser.guardNames
    self.guardStatements = parser.guardStatements
    self.actionNames = parser.actionNames
    self.constants = parser.constants
    self.rules = parser.rules
    self.states = parser.states
  }

  private static func stripComment(_ line: String) -> String {
    guard let range = line.range(of: " #") else { return line }
    return String(line[line.startIndex..<range.lowerBound])
  }

  private static func value(of line: String) -> String {
    let parts = line.split(separator: ":", maxSplits: 1)
    guard parts.count == keyValueParts else { return "" }
    return parts[1].trimmingCharacters(in: .whitespaces)
  }

  private static func scalarOrList(_ text: String) -> [String] {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return [trimmed] }
    let inner = trimmed.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
    if inner.isEmpty { return [] }
    return inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
  }

  private static func assign(_ text: String, into rule: inout ParsedRule) {
    let parts = text.split(separator: ":", maxSplits: 1)
    guard parts.count == keyValueParts else { return }
    let key = parts[0].trimmingCharacters(in: .whitespaces)
    let raw = parts[1].trimmingCharacters(in: .whitespaces)
    switch key {
    case "from":
      rule.from = scalarOrList(raw)

    case "event":
      rule.event = raw

    case "role":
      rule.role = raw

    case "guard":
      rule.condition = raw

    case "to":
      rule.destination = raw

    case "actions":
      rule.actions = scalarOrList(raw)

    default:
      break
    }
  }
}

/// The endpoints a model rule's role names; `custodian` is the proxy
/// endpoint.
internal func roles(of ruleRole: String) -> [EndpointRole] {
  switch ruleRole {
  case RuleRole.requester.rawValue:
    [.requester]

  case RuleRole.custodian.rawValue:
    [.proxy]

  default:
    [.requester, .proxy]
  }
}
