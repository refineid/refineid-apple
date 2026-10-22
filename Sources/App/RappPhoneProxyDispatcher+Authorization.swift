// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)

  import CardCore
  import Foundation
  import RappEngine

  /// Authorization handling and approval resolution for remote proxy operations.
  extension RappPhoneProxyDispatcher {
    /// What the holder is shown: the origin or document name, or a batch's
    /// whole document list in signing order (RAPP v26.10.21 §9.3, §11 item
    /// 1).
    private static func consentContext(for operation: RappOperationDriver.Operation) -> String? {
      guard operation.kind == .batchSignDocuments else { return operation.displayContext }
      return operation.documentNames.joined(separator: "\n")
    }

    internal func inspectPrerequisites(
      operationID: RappOperationIdentifier,
      operation: RappOperationDriver.Operation,
      coordinator: RappConnectionCoordinator
    ) async {
      guard prerequisitesExist(for: operation) else {
        try? await coordinator.requestInvalidOrUnsupported(operationID: operationID)
        return
      }
      try? await coordinator.prerequisitesComplete(operationID: operationID)
    }

    /// Asks the holder to consent to an action that needs a PIN; reads never
    /// come here (§8.2 items 3 and 6).
    internal func handleApproval(
      operationID: RappOperationIdentifier,
      operation: RappOperationDriver.Operation,
      coordinator: RappConnectionCoordinator
    ) async {
      guard let action = action(for: operation.kind) else {
        #if DEBUG
          HolderTrace.say("handleApproval: no consent defined for \(operation.kind)")
        #endif
        try? await coordinator.requestInvalidOrUnsupported(operationID: operationID)
        return
      }
      if await tryAutoApprove(operationID: operationID, operation: operation) {
        try? await coordinator.approve(operationID: operationID)
        return
      }
      #if DEBUG
        HolderTrace.say("handleApproval: asking holder authorization for \(operation.kind)")
      #endif
      // The consent view goes up first and the requester learns it is on
      // screen (§8.2 item 3).
      let decision = await ask(
        operationID: operationID, operation: operation, action: action, notice: nil,
        coordinator: coordinator)
      #if DEBUG
        HolderTrace.say("handleApproval: holder decided \(decision.summary)")
      #endif
      await resolveApprovalDecision(
        decision,
        operationID: operationID,
        operation: operation,
        coordinator: coordinator
      )
    }

    /// Shows the operation to the holder and waits for the decision.
    ///
    /// A `notice` says why the holder is asked again for the same
    /// operation: the card refused the PIN entered last (§10.2).
    internal func ask(
      operationID: RappOperationIdentifier,
      operation: RappOperationDriver.Operation,
      action: RappAuthorizationRequest.Action,
      notice: String?,
      coordinator: RappConnectionCoordinator
    ) async -> RappAuthorizationDecision {
      let request = RappAuthorizationRequest(
        requestID: requestID(for: operationID),
        requester: await Self.requesterName() ?? String(localized: "Paired device"),
        action: action,
        displayContext: Self.consentContext(for: operation),
        notice: notice
      )
      if notice == nil {
        try? await coordinator.reportProgress(operationID: operationID, event: .consentShown)
      }
      return await inbox.ask(request)
    }

    /// PIN 1 the phone may reuse by its own policy (§11 item 2).
    private func tryAutoApprove(
      operationID: RappOperationIdentifier,
      operation: RappOperationDriver.Operation
    ) async -> Bool {
      guard operation.kind == .browserAuthenticate else { return false }
      let isReader = await MainActor.run { CardPresence.shared.isReaderCardPresent }
      if isReader, let pin1 = await cachedReaderPin1() {
        #if DEBUG
          HolderTrace.say("handleApproval: using cached reader PIN 1")
        #endif
        pin1ByOperation[operationID] = pin1
        return true
      }
      if !isReader, let storedPin1 = CardCredentialStore.pin1Digits() {
        #if DEBUG
          HolderTrace.say("handleApproval: using stored unattended PIN 1")
        #endif
        pin1ByOperation[operationID] = storedPin1
        return true
      }
      return false
    }

    /// Takes the holder's decision: a denial ends the operation, an approval
    /// holds the PIN entered for the card command.
    internal func resolveApprovalDecision(
      _ decision: RappAuthorizationDecision,
      operationID: RappOperationIdentifier,
      operation: RappOperationDriver.Operation,
      coordinator: RappConnectionCoordinator
    ) async {
      guard await acceptDecision(decision, operationID: operationID, operation: operation) else {
        try? await coordinator.deny(operationID: operationID)
        return
      }
      try? await coordinator.approve(operationID: operationID)
    }

    /// Holds the PIN an approval carries for `operation`; false for a
    /// denial or a PIN of the wrong kind.
    internal func acceptDecision(
      _ decision: RappAuthorizationDecision,
      operationID: RappOperationIdentifier,
      operation: RappOperationDriver.Operation
    ) async -> Bool {
      switch decision {
      case .approvedBrowserAuthentication(let pin1):
        guard operation.kind == .browserAuthenticate else { return false }
        pin1ByOperation[operationID] = pin1.digits
        let isReader = await MainActor.run { CardPresence.shared.isReaderCardPresent }
        if isReader {
          await rememberReaderPin1(pin1.digits)
        }
        return true

      case .approvedDocumentSignature(let pin2):
        guard operation.kind == .signDocument || operation.kind == .batchSignDocuments else {
          return false
        }
        pin2Window.hold(pin2.digits)
        pin2ByOperation[operationID] = pin2.digits
        return true

      case .denied:
        return false
      }
    }

    private func prerequisitesExist(
      for operation: RappOperationDriver.Operation
    ) -> Bool {
      switch operation.kind {
      case .inspectCard, .readIdentity, .readAuthenticationCertificate,
        .readSignatureCertificate:
        return operation.keyProfile == nil
          && operation.algorithm == nil
          && operation.digest.isEmpty

      case .browserAuthenticate, .signDocument:
        return hasSigningDescriptor(operation)

      case .batchSignDocuments:
        return operation.keyProfile != nil && operation.algorithm != nil
          && !operation.digests.isEmpty
          && operation.documentNames.count == operation.digests.count
      }
    }

    private func hasSigningDescriptor(
      _ operation: RappOperationDriver.Operation
    ) -> Bool {
      operation.keyProfile != nil
        && operation.algorithm != nil
        && !operation.digest.isEmpty
    }

    internal func action(
      for kind: RappOperationDriver.OperationKind
    ) -> RappAuthorizationRequest.Action? {
      switch kind {
      case .browserAuthenticate:
        .browserAuthentication

      case .signDocument, .batchSignDocuments:
        .documentSignature

      case .inspectCard, .readIdentity, .readAuthenticationCertificate,
        .readSignatureCertificate:
        nil
      }
    }

    private func cachedReaderPin1() async -> String? {
      await MainActor.run {
        guard CardPresence.shared.isReaderCardPresent else {
          ReaderPin1Cache.shared.clear()
          return nil
        }
        return ReaderPin1Cache.shared.current()
      }
    }

    private func rememberReaderPin1(_ pin1: String) async {
      await MainActor.run {
        guard CardPresence.shared.isReaderCardPresent else { return }
        ReaderPin1Cache.shared.remember(pin1)
      }
    }
  }

#endif
