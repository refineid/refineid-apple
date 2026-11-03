// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A small reader for the flow-style lifecycle machines of the model.
///
/// The component machines are ``ModelReader``'s.
internal struct LifecycleModel {
  /// The three lifecycle machines, each with its one role.
  internal static let machineRoles = [
    ("requester_remote_use", "requester"),
    ("requester_view_of_custodian", "requester"),
    ("custodian_service", "custodian"),
  ]

  private static let sectionIndent = 2
  private static let itemIndent = 4
  private static let keyValueParts = 2
  /// The `- ` that opens a block list item.
  private static let itemMarker = "- "

  internal let machines: [String: LifecycleMachine]

  internal init(text: String) {
    let names = Set(Self.machineRoles.map(\.0))
    var read: [String: LifecycleMachine] = [:]
    var current: String?
    var section = ""
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(rawLine)
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
      let indent = line.prefix { $0 == " " }.count
      if indent == 0 {
        let name = String(line.split(separator: ":", maxSplits: 1)[0])
        current = names.contains(name) ? name : nil
        if let current { read[current] = LifecycleMachine() }
        continue
      }
      guard let name = current, var machine = read[name] else { continue }
      if indent == Self.sectionIndent {
        let parts = Self.keyValue(trimmed)
        section = parts.key
        switch parts.key {
        case "role":
          machine.role = parts.value

        case "initial":
          machine.initial = parts.value

        default:
          break
        }
      } else if indent >= Self.itemIndent {
        Self.feed(trimmed, section: section, into: &machine)
      }
      read[name] = machine
    }
    machines = read
  }

  private static func feed(_ item: String, section: String, into machine: inout LifecycleMachine) {
    switch section {
    case "states", "events":
      let name = String(stripComment(String(item.dropFirst(itemMarker.count))))
        .trimmingCharacters(in: .whitespaces)
      if section == "states" { machine.states.append(name) } else { machine.events.append(name) }

    case "transitions", "ignored", "cannot_happen":
      guard let open = item.firstIndex(of: "{"), let close = item.lastIndex(of: "}") else {
        return
      }
      let entry = flowEntry(String(item[item.index(after: open)..<close]))
      switch section {
      case "transitions":
        machine.transitions.append(entry)

      case "ignored":
        machine.ignored.append(entry)

      default:
        machine.cannotHappen.append(entry)
      }

    case "presentation":
      let parts = keyValue(item)
      machine.presentation[parts.key] = unquoted(parts.value)

    default:
      break
    }
  }

  private static func flowEntry(_ body: String) -> LifecycleEntry {
    var entry = LifecycleEntry()
    for field in topLevelFields(body) {
      let parts = keyValue(field)
      let values = list(parts.value)
      switch parts.key {
      case "from":
        entry.from = values

      case "event":
        entry.event = values

      case "guard":
        entry.guards = values

      case "role":
        entry.role = parts.value

      case "to":
        entry.destination = parts.value

      case "actions":
        entry.actions = values

      case "reason":
        entry.reason = unquoted(parts.value)

      default:
        break
      }
    }
    return entry
  }

  /// Splits `body` at the commas outside brackets and quotes.
  private static func topLevelFields(_ body: String) -> [String] {
    var fields: [String] = []
    var current = ""
    var depth = 0
    var quoted = false
    for character in body {
      switch character {
      case "\"":
        quoted.toggle()

      case "[" where !quoted:
        depth += 1

      case "]" where !quoted:
        depth -= 1

      case "," where !quoted && depth == 0:
        fields.append(current)
        current = ""
        continue

      default:
        break
      }
      current.append(character)
    }
    fields.append(current)
    return fields.map { $0.trimmingCharacters(in: .whitespaces) }
  }

  private static func keyValue(_ text: String) -> (key: String, value: String) {
    let parts = text.split(separator: ":", maxSplits: 1)
    let key = parts[0].trimmingCharacters(in: .whitespaces)
    guard parts.count == keyValueParts else { return (key, "") }
    let value = parts[1].trimmingCharacters(in: .whitespaces)
    return (key, String(stripComment(value)).trimmingCharacters(in: .whitespaces))
  }

  private static func list(_ text: String) -> [String] {
    guard text.hasPrefix("["), text.hasSuffix("]") else { return text.isEmpty ? [] : [text] }
    let names = text.dropFirst().dropLast().split(separator: ",")
    return names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
  }

  private static func unquoted(_ text: String) -> String {
    let quote = CharacterSet(charactersIn: "\"")
    return text.trimmingCharacters(in: quote)
  }

  private static func stripComment(_ text: String) -> Substring {
    guard !text.hasPrefix("\""), let range = text.range(of: " #") else { return Substring(text) }
    return text[text.startIndex..<range.lowerBound]
  }
}
