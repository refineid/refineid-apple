// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import XCTest

@testable import RefineID

internal final class CardSetupStateMachineTests: XCTestCase {
  private func loadGrammar() throws -> ParsedGrammar {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let url =
      repositoryRoot
      .appendingPathComponent("Documentation")
      .appendingPathComponent("card-setup-state-machine.scxml")
    let parser = XMLParser(contentsOf: url)
    let delegate = GrammarParserDelegate()
    parser?.delegate = delegate

    XCTAssertEqual(
      parser?.parse(), true, parser?.parserError?.localizedDescription ?? "SCXML parse failed")
    XCTAssertTrue(delegate.errors.isEmpty, delegate.errors.joined(separator: "\n"))

    return ParsedGrammar(
      initialState: try XCTUnwrap(delegate.initialState),
      states: delegate.states,
      transitions: delegate.transitions
    )
  }

  internal func testSwiftTransitionTableExactlyMatchesCanonicalSCXML() throws {
    let grammar = try loadGrammar()

    XCTAssertEqual(grammar.initialState, CardSetupStateMachine.initialState)
    XCTAssertEqual(grammar.states, Set(CardSetupStateMachine.State.allCases))
    XCTAssertEqual(
      grammar.transitions.count,
      Set(grammar.transitions).count,
      "SCXML contains duplicate transitions"
    )
    XCTAssertEqual(
      CardSetupStateMachine.transitions.count,
      Set(CardSetupStateMachine.transitions).count,
      "Swift contains duplicate transitions"
    )
    XCTAssertEqual(Set(grammar.transitions), Set(CardSetupStateMachine.transitions))
  }

  internal func testEveryStateEventPairMatchesGrammarTransitionOrRejection() throws {
    let grammar = try loadGrammar()
    let transitions = Dictionary(grouping: grammar.transitions) { transition in
      StateEvent(state: transition.source, event: transition.event)
    }

    for state in CardSetupStateMachine.State.allCases {
      for event in CardSetupStateMachine.Event.allCases {
        let expected = transitions[StateEvent(state: state, event: event), default: []]
        XCTAssertLessThanOrEqual(expected.count, 1, "Grammar is ambiguous for \(state), \(event)")

        switch (expected.first, CardSetupStateMachine.reduce(state: state, event: event)) {
        case (.some(let transition), .transitioned(let target)):
          XCTAssertEqual(target, transition.target, "Mismatch for \(state), \(event)")

        case (.none, .rejected):
          break

        default:
          XCTFail("Grammar/reducer disagreement for \(state), \(event)")
        }
      }
    }
  }

  internal func testEveryDeclaredStateIsReachableFromInitialState() {
    var reached: Set<CardSetupStateMachine.State> = [CardSetupStateMachine.initialState]
    var frontier = Array(reached)

    while let source = frontier.popLast() {
      for transition in CardSetupStateMachine.transitions where transition.source == source {
        if reached.insert(transition.target).inserted {
          frontier.append(transition.target)
        }
      }
    }

    XCTAssertEqual(reached, Set(CardSetupStateMachine.State.allCases))
  }

  internal func testClassificationStatesHandleEveryCardOutcome() {
    let outcomes: Set<CardSetupStateMachine.Event> = [
      .classificationActivated,
      .classificationRecoveryRequired,
      .classificationActivationRequired,
      .classificationWrongCardAccessNumber,
      .classificationFailed,
    ]

    for state in [
      CardSetupStateMachine.State.classifyingBrowser,
      .classifyingManagementHome,
      .classifyingManagementIdentity,
    ] {
      let handled = Set(
        CardSetupStateMachine.transitions
          .filter { $0.source == state }
          .map(\.event)
      )
      XCTAssertEqual(handled, outcomes, "Incomplete classification outcomes for \(state)")
    }
  }

  internal func testCardOutcomeRoutesRespectPurpose() {
    assertTransition(.classifyingBrowser, .classificationActivated, .registeringBrowser)
    assertTransition(.classifyingManagementHome, .classificationActivated, .pinManagementHome)
    assertTransition(
      .classifyingManagementIdentity, .classificationActivated, .pinManagementIdentity)
    assertTransition(.classifyingBrowser, .classificationRecoveryRequired, .pinManagementHome)
    assertTransition(
      .classifyingManagementHome, .classificationRecoveryRequired, .pinManagementHome)
    assertTransition(
      .classifyingManagementIdentity, .classificationRecoveryRequired, .pinManagementIdentity)
    assertTransition(.classifyingBrowser, .classificationActivationRequired, .activationHome)
    assertTransition(.classifyingManagementHome, .classificationActivationRequired, .activationHome)
    assertTransition(
      .classifyingManagementIdentity, .classificationActivationRequired, .activationIdentity)
  }

  internal func testDestinationDismissalPreservesIdentityOrigin() {
    assertTransition(.activationHome, .destinationDismissed, .home)
    assertTransition(.activationIdentity, .destinationDismissed, .identityHome)
    assertTransition(.pinManagementHome, .destinationDismissed, .home)
    assertTransition(.pinManagementIdentity, .destinationDismissed, .identityHome)
    assertTransition(.documentSigningHome, .destinationDismissed, .home)
    assertTransition(.documentSigningIdentity, .destinationDismissed, .identityHome)
  }

  internal func testDestinationProjectionIsCompleteAndUnambiguous() {
    let expected: [CardSetupStateMachine.State: CardSetupStateMachine.Destination] = [
      .activationHome: .activation,
      .activationIdentity: .activation,
      .pinManagementHome: .pinManagement,
      .pinManagementIdentity: .pinManagement,
      .documentSigningHome: .signDocuments,
      .documentSigningIdentity: .signDocuments,
    ]

    for state in CardSetupStateMachine.State.allCases {
      XCTAssertEqual(state.destination, expected[state], "Unexpected destination for \(state)")
    }
  }

  internal func testIdentityOriginSurvivesEveryManagementClassificationFailure() {
    assertTransition(
      .classifyingManagementIdentity,
      .classificationWrongCardAccessNumber,
      .identityHome)
    assertTransition(
      .classifyingManagementIdentity,
      .classificationFailed,
      .identityHome)
  }

  private func assertTransition(
    _ source: CardSetupStateMachine.State,
    _ event: CardSetupStateMachine.Event,
    _ target: CardSetupStateMachine.State,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(
      CardSetupStateMachine.reduce(state: source, event: event),
      .transitioned(target: target),
      file: file,
      line: line
    )
  }
}
