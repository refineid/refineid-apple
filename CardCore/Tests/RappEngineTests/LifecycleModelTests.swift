// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP v26.11.2 lifecycle machines and their scenarios (section 4.7)")
internal struct LifecycleModelTests {
  private enum Outcome {
    static let transition = "transition"
    static let ignored = "ignored"
    static let cannotHappen = "cannot_happen"
  }

  private static let connected = "connected"
  private static let ended = "ended"
  private static let withdrawn = "withdrawn"
  private static let remoteCardShown = "the remote card"
  private static let noRemoteCardShown = "no remote card"
  private static let forgotLine = "show_peer_forgot"
  private static let dial = "open_session_dial"
  private static let announcements: Set<String> = ["record_appeared", "advertisement_appeared"]
  private static let holdingActions: Set<String> = ["schedule_redial", "start_offer_grace"]
  private static let switchEvents: Set<String> = ["holder_turns_on", "holder_turns_off"]
  private static let offerCancel = "cancel_offer"
  private static let bothRoles = "both"

  private func model(_ filePath: String = #filePath) throws -> LifecycleModel {
    try StateModelFile.lifecycle(filePath: filePath)
  }

  @Test("Every state and event of a lifecycle machine has exactly one answer")
  internal func everyCellHasOneAnswer() throws {
    let model = try model()
    let declared = try StateModelFile.read(filePath: #filePath)
    for (name, role) in LifecycleModel.machineRoles {
      let machine = try #require(model.machines[name], "\(name)")
      #expect(machine.role == role, "\(name) names its role")
      #expect(machine.states.contains(machine.initial), "\(name) initial")
      for rule in machine.transitions {
        #expect(machine.states.contains(rule.destination ?? ""), "\(name) target")
        #expect(Set(rule.actions).isSubset(of: declared.actionNames), "\(name) actions")
        #expect(Set(rule.guards).isSubset(of: declared.guardNames), "\(name) guards")
      }
      for entry in machine.ignored + machine.cannotHappen {
        #expect(!(entry.reason ?? "").isEmpty, "\(name): an entry without a reason")
      }
      let cells = LifecycleCells(machine)
      for state in machine.states {
        for event in machine.events {
          #expect(cells.hasOneAnswer(state, event), "\(name): \(state) / \(event)")
        }
      }
    }
  }

  @Test("The requester shows the custodian only through its card")
  internal func requesterShowsNoCustodianState() throws {
    let view = try #require(try model().machines["requester_view_of_custodian"])
    for state in view.states {
      let shown = try #require(view.presentation[state], "\(state)")
      let isConnected = state == Self.connected
      #expect(shown.hasPrefix(Self.remoteCardShown) == isConnected, "\(state)")
      if !isConnected, state != Self.ended {
        #expect(shown.hasPrefix(Self.noRemoteCardShown), "\(state)")
      }
    }
    let shownActions = Set(view.transitions.flatMap(\.actions).filter { $0.hasPrefix("show_") })
    #expect(shownActions == [Self.forgotLine])
  }

  @Test("A withdrawn custodian is dialed only after it announces itself")
  internal func withdrawnWaitsForAnnouncement() throws {
    let view = try #require(try model().machines["requester_view_of_custodian"])
    for rule in view.transitions where rule.from.contains(Self.withdrawn) {
      if rule.actions.contains(Self.dial) {
        #expect(Set(rule.event).isSubset(of: Self.announcements), "\(rule.event)")
      }
      #expect(Self.holdingActions.isDisjoint(with: rule.actions))
    }
  }

  @Test("The custodian's switch never touches a pairing")
  internal func custodianSwitchKeepsPairings() throws {
    let service = try #require(try model().machines["custodian_service"])
    let rules = service.transitions.filter { !Self.switchEvents.isDisjoint(with: $0.event) }
    #expect(!rules.isEmpty)
    for action in rules.flatMap(\.actions) {
      #expect(!action.contains("pair") || action == Self.offerCancel, "\(action)")
      #expect(!action.contains("revok") && !action.contains("forget"), "\(action)")
    }
  }

  @Test("The lifecycle constants agree with each other and with the engine")
  internal func constantsAgree() throws {
    let constants = try StateModelFile.read(filePath: #filePath).constants
    #expect(constants["redial_window_ms"] == RedialWindow.milliseconds)
    #expect(constants["redial_window_ms"] == constants["identity_offer_grace_ms"])
    #expect(constants["revocation_attempt_bound_ms"] == RevocationAttemptBound.milliseconds)
    #expect(constants["display_name_max_bytes"] == UInt64(RappDisplayName.maximumBytes))
    #expect(
      (constants["session_silence_limit_ms"] ?? 0) < (constants["redial_window_ms"] ?? 0))
    #expect(
      (constants["revocation_attempt_bound_ms"] ?? 0)
        > (constants["quit_withdrawal_bound_ms"] ?? 0))
  }

  @Test("Every lifecycle scenario walks the model; pairing and session ones walk the engine")
  internal func scenariosWalk() throws {
    let model = try model()
    let corpus = try LifecycleCorpus.read(filePath: #filePath)
    #expect(corpus.format == "fi.refineid.rapp.lifecycle-vectors")
    #expect(corpus.protocolDocumentVersion == StateModelFile.expectedDocumentVersion)
    #expect(!corpus.scenarios.isEmpty)
    for scenario in corpus.scenarios {
      if let machine = model.machines[scenario.machine] {
        walk(scenario, through: machine)
      } else {
        try walkEngine(scenario)
      }
    }
  }

  /// Walks `scenario` through a lifecycle machine of the model.
  private func walk(_ scenario: LifecycleScenario, through machine: LifecycleMachine) {
    var state = scenario.start
    for step in scenario.steps {
      let label = "\(scenario.name) / \(state) / \(step.event)"
      let given = Set(step.guards)
      let matching = machine.transitions.filter { rule in
        rule.from.contains(state) && rule.event.contains(step.event)
          && (rule.role.map { $0 == Self.bothRoles || $0 == scenario.role } ?? true)
          && Set(rule.guards).isSubset(of: given)
      }
      func says(_ entries: [LifecycleEntry]) -> Bool {
        entries.contains { entry in
          entry.from.contains(state) && entry.event.contains(step.event)
            && Set(entry.guards).isSubset(of: given)
        }
      }
      switch step.outcome {
      case Outcome.transition:
        #expect(matching.count == 1, "\(label): one rule applies")
        guard let rule = matching.first else { return }
        #expect(rule.destination == step.state, "\(label)")
        #expect(rule.actions == step.actions?.names, "\(label)")
        state = rule.destination ?? state

      case Outcome.ignored:
        #expect(matching.isEmpty && says(machine.ignored), "\(label)")

      default:
        #expect(matching.isEmpty && says(machine.cannotHappen), "\(label)")
      }
    }
  }

  /// Walks a pairing or session scenario through the engine's own tables.
  private func walkEngine(_ scenario: LifecycleScenario) throws {
    let role: EndpointRole = scenario.role == RuleRole.custodian.rawValue ? .proxy : .requester
    var state = scenario.start
    for step in scenario.steps {
      let label = "\(scenario.name) / \(state) / \(step.event)"
      var guards = RappGuards.noneSatisfied
      for name in step.guards {
        guards.set(try #require(RappGuard(rawValue: name), "\(label)"), true)
      }
      let fired: (state: String, actions: [String])?
      switch scenario.machine {
      case "pairing":
        let transition = PairingState.transition(
          from: try #require(PairingState(rawValue: state), "\(label)"),
          on: try #require(PairingEvent(rawValue: step.event), "\(label)"),
          role: role, guards: guards)
        fired = transition.map { ($0.state.rawValue, $0.actions.map(\.rawValue)) }

      default:
        let transition = SessionState.transition(
          from: try #require(SessionState(rawValue: state), "\(label)"),
          on: try #require(SessionEvent(rawValue: step.event), "\(label)"),
          role: role, guards: guards)
        fired = transition.map { ($0.state.rawValue, $0.actions.map(\.rawValue)) }
      }
      if step.outcome == Outcome.transition {
        let transition = try #require(fired, "\(label): one rule applies")
        #expect(transition.state == step.state, "\(label)")
        #expect(transition.actions == step.actions?.names, "\(label)")
        state = transition.state
      } else {
        #expect(fired == nil, "\(label)")
      }
    }
  }
}
