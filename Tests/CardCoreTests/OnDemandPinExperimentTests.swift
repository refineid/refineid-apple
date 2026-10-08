// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// Tests verifying the on-demand PIN1 experiment, candidate preservation,
/// volatile accepted memory promotion, and rejection/cancellation protection.
@Suite(.serialized)
internal struct OnDemandPinExperimentTests {
  private static let testInstanceA = makeInstance(serial: "TEST00001")
  private static let testInstanceB = makeInstance(serial: "TEST00002")
  private static let testCorrelationID = "corr-test-1234"
  private static let dummyPin = "1234"

  private static func makeInstance(serial: String) -> CardInstanceIdentifier {
    guard
      let tokenSerial = TokenSerial(value: serial),
      let instance = CardInstanceIdentifier(tokenSerial: tokenSerial)
    else {
      fatalError("Invalid serial")
    }
    return instance
  }

  private static func makePin() -> Pin1 {
    guard let pin = Pin1(digits: dummyPin) else { fatalError("Valid PIN") }
    return pin
  }

  private func present(_ candidate: consuming Pin1?) -> Bool {
    let has = candidate != nil
    _ = candidate
    return has
  }

  @Test
  internal func experimentIsOffUntilEnabled() {
    OnDemandPinExperiment.reset()
    defer { OnDemandPinExperiment.reset() }
    #expect(!OnDemandPinExperiment.isEnabled)
    OnDemandPinExperiment.setEnabled(true)
    #expect(OnDemandPinExperiment.isEnabled)
    OnDemandPinExperiment.setEnabled(false)
    #expect(!OnDemandPinExperiment.isEnabled)
  }

  @Test
  internal func testOverrideControlsExperimentState() {
    OnDemandPinExperiment.setTestOverride(.forcedActive)
    #expect(OnDemandPinExperiment.isEnabled)

    OnDemandPinExperiment.setTestOverride(.forcedInactive)
    #expect(!OnDemandPinExperiment.isEnabled)

    OnDemandPinExperiment.setTestOverride(.unconfigured)
  }

  @Test
  internal func nativePinPromptDoesNotStartPaceBeforePinIsAvailable() {
    #expect(
      !OnDemandPinExperiment.needsSigningField(
        isRegistrationField: false,
        experimentEnabled: true,
        pinAvailable: false
      ))
    #expect(
      OnDemandPinExperiment.needsSigningField(
        isRegistrationField: false,
        experimentEnabled: true,
        pinAvailable: true
      ))
    #expect(
      OnDemandPinExperiment.needsSigningField(
        isRegistrationField: false,
        experimentEnabled: false,
        pinAvailable: false
      ))
    #expect(
      !OnDemandPinExperiment.needsSigningField(
        isRegistrationField: true,
        experimentEnabled: true,
        pinAvailable: true
      ))
  }

  @Test
  internal func fieldExpiryBeforeVerifyPreservesCandidateAcrossSessions() {
    OnDemandPinExperiment.setTestOverride(.forcedActive)
    defer { OnDemandPinExperiment.setTestOverride(.unconfigured) }

    let candidateStore = TransientCandidatePin1()
    let opID = UUID()
    let staged = candidateStore.stage(
      digits: Self.dummyPin,
      for: Self.testInstanceA,
      operationID: opID,
      correlationID: Self.testCorrelationID
    )
    #expect(staged)
    #expect(candidateStore.hasPending(for: Self.testInstanceA))

    guard let firstCheckout = candidateStore.checkout(for: Self.testInstanceA) else {
      Issue.record("Expected candidate on first checkout")
      return
    }
    _ = consume firstCheckout
    #expect(candidateStore.hasPending(for: Self.testInstanceA))

    guard let replacementCheckout = candidateStore.checkout(for: Self.testInstanceA) else {
      Issue.record("Expected candidate preserved on replacement session checkout")
      return
    }
    _ = consume replacementCheckout
    #expect(candidateStore.hasPending(for: Self.testInstanceA))
  }

  @Test
  internal func successfulAuthenticationPromotesToAcceptedMemory() {
    OnDemandPinExperiment.setTestOverride(.forcedActive)
    defer { OnDemandPinExperiment.setTestOverride(.unconfigured) }

    let candidateStore = TransientCandidatePin1()
    let acceptedStore = VolatileAcceptedPin1()

    let opID = UUID()
    candidateStore.stage(
      digits: Self.dummyPin,
      for: Self.testInstanceA,
      operationID: opID,
      correlationID: Self.testCorrelationID
    )
    guard let candidate = candidateStore.checkout(for: Self.testInstanceA) else {
      Issue.record("Expected candidate")
      return
    }

    acceptedStore.store(candidate, for: Self.testInstanceA)
    candidateStore.clear(for: Self.testInstanceA)

    #expect(!candidateStore.hasPending(for: Self.testInstanceA))
    #expect(acceptedStore.hasPin(for: Self.testInstanceA))

    guard let reused = acceptedStore.checkout(for: Self.testInstanceA) else {
      Issue.record("Expected reused accepted PIN")
      return
    }
    _ = consume reused
  }

  @Test
  internal func subsequentRequestsReuseAcceptedMemoryAcrossSessionRecreation() {
    OnDemandPinExperiment.setTestOverride(.forcedActive)
    defer { OnDemandPinExperiment.setTestOverride(.unconfigured) }

    let acceptedStore = VolatileAcceptedPin1()
    acceptedStore.store(Self.makePin(), for: Self.testInstanceA)

    #expect(acceptedStore.hasPin(for: Self.testInstanceA))
    #expect(!acceptedStore.hasPin(for: Self.testInstanceB))

    for _ in 1...3 {
      guard let checkedOut = acceptedStore.checkout(for: Self.testInstanceA) else {
        Issue.record("Expected checked out PIN from accepted memory")
        return
      }
      _ = consume checkedOut
    }
  }

  @Test
  internal func cardRejectionClearsStateAndPreventsAutomaticReplay() {
    OnDemandPinExperiment.setTestOverride(.forcedActive)
    defer { OnDemandPinExperiment.setTestOverride(.unconfigured) }

    let candidateStore = TransientCandidatePin1()
    let acceptedStore = VolatileAcceptedPin1()

    let opID = UUID()
    candidateStore.stage(
      digits: Self.dummyPin,
      for: Self.testInstanceA,
      operationID: opID,
      correlationID: Self.testCorrelationID
    )
    acceptedStore.store(Self.makePin(), for: Self.testInstanceA)

    candidateStore.clear(for: Self.testInstanceA)
    acceptedStore.clear(for: Self.testInstanceA)

    #expect(!candidateStore.hasPending(for: Self.testInstanceA))
    #expect(!acceptedStore.hasPin(for: Self.testInstanceA))
    let hasCandidateA = present(candidateStore.checkout(for: Self.testInstanceA))
    let hasAcceptedA = present(acceptedStore.checkout(for: Self.testInstanceA))
    #expect(!hasCandidateA)
    #expect(!hasAcceptedA)
  }

  @Test
  internal func cancellationTiedToOperationIdProtectsNewerCandidates() {
    OnDemandPinExperiment.setTestOverride(.forcedActive)
    defer { OnDemandPinExperiment.setTestOverride(.unconfigured) }

    let candidateStore = TransientCandidatePin1()
    let oldOpID = UUID()
    let newOpID = UUID()

    candidateStore.stage(
      digits: Self.dummyPin,
      for: Self.testInstanceA,
      operationID: newOpID,
      correlationID: "corr-new"
    )

    candidateStore.cancel(operationID: oldOpID)
    #expect(candidateStore.hasPending(for: Self.testInstanceA))

    candidateStore.cancel(operationID: newOpID)
    #expect(!candidateStore.hasPending(for: Self.testInstanceA))
  }

  @Test
  internal func cardMismatchClearsCandidateToPreventLeakage() {
    OnDemandPinExperiment.setTestOverride(.forcedActive)
    defer { OnDemandPinExperiment.setTestOverride(.unconfigured) }

    let candidateStore = TransientCandidatePin1()
    candidateStore.stage(
      digits: Self.dummyPin,
      for: Self.testInstanceA,
      operationID: UUID(),
      correlationID: Self.testCorrelationID
    )

    let hasCandidateB = present(candidateStore.checkout(for: Self.testInstanceB))
    #expect(!hasCandidateB)
    #expect(!candidateStore.hasPending(for: Self.testInstanceA))
  }

  @Test
  internal func experimentDisabledBehaviorLeavesCandidateStoreInactive() {
    OnDemandPinExperiment.setTestOverride(.forcedInactive)
    defer { OnDemandPinExperiment.setTestOverride(.unconfigured) }

    let candidateStore = TransientCandidatePin1()
    let staged = candidateStore.stage(
      digits: Self.dummyPin,
      for: Self.testInstanceA,
      operationID: UUID(),
      correlationID: Self.testCorrelationID
    )
    #expect(!staged)
    #expect(!candidateStore.hasPending(for: Self.testInstanceA))
    let hasCandidateA = present(candidateStore.checkout(for: Self.testInstanceA))
    #expect(!hasCandidateA)
  }

  @Test
  internal func experimentDisabledBehaviorLeavesAcceptedStoreInactive() {
    OnDemandPinExperiment.setTestOverride(.forcedInactive)
    defer { OnDemandPinExperiment.setTestOverride(.unconfigured) }

    let acceptedStore = VolatileAcceptedPin1()
    acceptedStore.store(Self.makePin(), for: Self.testInstanceA)

    #expect(!acceptedStore.hasPin(for: Self.testInstanceA))
    let hasAcceptedA = present(acceptedStore.checkout(for: Self.testInstanceA))
    #expect(!hasAcceptedA)
  }

  @Test
  internal func prepareAcceptanceDoesNotStoreUntilCardVerificationSucceedsAndDiscardsOnFailure() {
    OnDemandPinExperiment.setTestOverride(.forcedActive)
    defer { OnDemandPinExperiment.setTestOverride(.unconfigured) }

    let acceptedStore = VolatileAcceptedPin1()
    let pin = Self.makePin()

    let pending = acceptedStore.prepareAcceptance(of: pin, for: Self.testInstanceA)
    let isPendingActive = pending != nil
    #expect(isPendingActive)
    #expect(!acceptedStore.hasPin(for: Self.testInstanceA))
    let hasAcceptedA = present(acceptedStore.checkout(for: Self.testInstanceA))
    #expect(!hasAcceptedA)

    _ = pending
    #expect(!acceptedStore.hasPin(for: Self.testInstanceA))

    let pendingSuccess = acceptedStore.prepareAcceptance(
      of: Self.makePin(),
      for: Self.testInstanceA
    )
    if let pendingSuccess {
      acceptedStore.commit(pendingSuccess)
    }
    #expect(acceptedStore.hasPin(for: Self.testInstanceA))
    guard let committedPin = acceptedStore.checkout(for: Self.testInstanceA) else {
      Issue.record("Expected committed PIN")
      return
    }
    _ = consume committedPin
  }
}
