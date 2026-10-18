// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP state tables against the vendored formal model")
internal struct StateConformanceTests {
  /// Rule counts the model declares, per component machine.
  private static let expectedRuleCounts = [("pairing", 22), ("session", 31), ("operation", 39)]

  /// An action the perturbed control appends so the comparison must notice.
  private static let perturbingAction = "hide_pairing_code"

  private func reader(_ filePath: String = #filePath) throws -> ModelReader {
    try StateModelFile.read(filePath: filePath)
  }

  /// Entries the formal model defines, expanded per state and role.
  private func modelEntries(_ reader: ModelReader) -> Set<ModelEntry> {
    var entries: Set<ModelEntry> = []
    for (machine, rules) in reader.rules {
      for rule in rules {
        for from in rule.from {
          for role in roles(of: rule.role) {
            entries.insert(
              ModelEntry(
                machine: machine, from: from, event: rule.event, role: role.rawValue,
                destination: rule.destination, actions: rule.actions.joined(separator: ",")))
          }
        }
      }
    }
    return entries
  }

  private func entries<State, Event>(
    machine: String,
    rules: [RappRule<State, Event>],
    transition: (State, Event, EndpointRole) -> RappTransition<State>?
  ) -> Set<ModelEntry>
  where
    State: RawRepresentable, State.RawValue == String,
    Event: RawRepresentable, Event.RawValue == String
  {
    var collected: Set<ModelEntry> = []
    for rule in rules {
      for from in rule.from {
        for role in roles(of: rule.role.rawValue) {
          guard let fired = transition(from, rule.event, role) else { continue }
          collected.insert(
            ModelEntry(
              machine: machine, from: from.rawValue, event: rule.event.rawValue,
              role: role.rawValue, destination: fired.state.rawValue,
              actions: fired.actions.map(\.rawValue).joined(separator: ",")))
        }
      }
    }
    return collected
  }

  /// Entries the Swift tables define, resolved through the same lookup the
  /// engine uses so the tables cannot pass by being read a second way.
  private func swiftEntries() -> Set<ModelEntry> {
    entries(machine: "pairing", rules: RappModelTables.pairing, transition: PairingState.transition)
      .union(
        entries(
          machine: "session", rules: RappModelTables.session,
          transition: SessionState.transition)
      )
      .union(
        entries(
          machine: "operation", rules: RappModelTables.operation,
          transition: OperationState.transition)
      )
  }

  @Test("The transcription names the revision it was made from")
  internal func documentVersion() throws {
    #expect(try reader().documentVersion == StateModelFile.expectedDocumentVersion)
  }

  @Test("Every rule in the model is implemented")
  internal func everyModelRuleIsImplemented() throws {
    let missing = modelEntries(try reader()).subtracting(swiftEntries())
    #expect(missing.isEmpty, "\(missing.sorted().map(\.label))")
  }

  @Test("No implemented rule is absent from the model")
  internal func noRuleExistsOutsideTheModel() throws {
    let extra = swiftEntries().subtracting(modelEntries(try reader()))
    #expect(extra.isEmpty, "\(extra.sorted().map(\.label))")
  }

  @Test("Each component machine carries the rule count the model declares")
  internal func ruleCounts() throws {
    let rules = try reader().rules
    for (machine, expected) in Self.expectedRuleCounts {
      #expect(rules[machine]?.count == expected, "\(machine)")
    }
  }

  @Test("No state, event, and role is governed twice")
  internal func rulesDoNotOverlap() throws {
    var seen: Set<String> = []
    var duplicates: [String] = []
    for entry in modelEntries(try reader()) {
      let key = "\(entry.machine)|\(entry.from)|\(entry.event)|\(entry.role)"
      if seen.contains(key) { duplicates.append(key) }
      seen.insert(key)
    }
    #expect(duplicates.isEmpty, "\(duplicates)")
  }

  @Test("The guard and action vocabularies match the model")
  internal func vocabularyMatches() throws {
    let model = try reader()
    #expect(Set(RappGuard.allCases.map(\.rawValue)) == model.guardNames)
    #expect(Set(RappAction.allCases.map(\.rawValue)) == model.actionNames)
  }

  @Test("Every action and guard a rule names is declared")
  internal func rulesNameDeclaredVocabulary() throws {
    let model = try reader()
    var used: Set<String> = []
    var conditions: Set<String> = []
    for rules in model.rules.values {
      for rule in rules {
        used.formUnion(rule.actions)
        if let condition = rule.condition { conditions.insert(condition) }
      }
    }
    #expect(used.subtracting(model.actionNames).isEmpty)
    #expect(conditions.subtracting(model.guardNames).isEmpty)
  }

  @Test("A perturbed action list is detected as a discrepancy")
  internal func perturbedActionListIsDetected() throws {
    let model = modelEntries(try reader())
    let victim = try #require(model.min())
    var perturbed = model
    perturbed.remove(victim)
    perturbed.insert(
      ModelEntry(
        machine: victim.machine, from: victim.from, event: victim.event, role: victim.role,
        destination: victim.destination, actions: victim.actions + "," + Self.perturbingAction))
    #expect(!perturbed.subtracting(swiftEntries()).isEmpty)
  }
}
