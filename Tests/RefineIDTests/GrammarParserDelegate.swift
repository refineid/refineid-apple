// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import RefineID

internal final class GrammarParserDelegate: NSObject, XMLParserDelegate {
  internal var initialState: CardSetupStateMachine.State?
  internal var states: Set<CardSetupStateMachine.State> = []
  internal var transitions: [CardSetupStateMachine.Transition] = []
  internal var errors: [String] = []

  private var currentState: CardSetupStateMachine.State?

  internal func parser(
    _: XMLParser,
    didStartElement elementName: String,
    namespaceURI _: String?,
    qualifiedName _: String?,
    attributes attributeDict: [String: String]
  ) {
    switch elementName {
    case "scxml":
      guard let rawInitial = attributeDict["initial"],
        let initial = CardSetupStateMachine.State(rawValue: rawInitial)
      else {
        errors.append("Unknown or missing SCXML initial state")
        return
      }
      initialState = initial

    case "state":
      guard let rawState = attributeDict["id"],
        let state = CardSetupStateMachine.State(rawValue: rawState)
      else {
        errors.append("Unknown or missing SCXML state id")
        return
      }
      if !states.insert(state).inserted {
        errors.append("Duplicate SCXML state id \(rawState)")
      }
      currentState = state

    case "transition":
      guard let source = currentState,
        let rawEvent = attributeDict["event"],
        let event = CardSetupStateMachine.Event(rawValue: rawEvent),
        let rawTarget = attributeDict["target"],
        let target = CardSetupStateMachine.State(rawValue: rawTarget)
      else {
        errors.append("Unknown or incomplete transition \(attributeDict)")
        return
      }
      transitions.append(.init(source: source, event: event, target: target))

    default:
      break
    }
  }

  internal func parser(
    _: XMLParser,
    didEndElement elementName: String,
    namespaceURI _: String?,
    qualifiedName _: String?
  ) {
    if elementName == "state" {
      currentState = nil
    }
  }
}
