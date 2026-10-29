// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)

  import CardCore
  import Foundation
  import RappEngine

  /// The PIN an operation needs, taken on the phone (RAPP v26.10.29 §8.2
  /// item 3): from memory for a browser authentication whose PIN 1 the phone
  /// holds, else from a prompt, which is the holder's consent.
  extension RappPhoneProxyDispatcher {
    /// The documents a signing prompt names, in signing order (§9.3).
    ///
    /// One signature names its document and a batch its whole list. An
    /// authentication names only the computer, never the requester's
    /// context (§11 item 1).
    private static func promptDocuments(for operation: RappOperationDriver.Operation) -> [String] {
      switch operation.kind {
      case .batchSignDocuments:
        return operation.documentNames

      case .signDocument:
        return operation.displayContext.map { [$0] } ?? []

      default:
        return []
      }
    }

    internal func inspectPrerequisites(
      operationID: RappOperationIdentifier,
      operation: RappOperationDriver.Operation,
      coordinator: RappConnectionCoordinator
    ) async {
      guard prerequisitesExist(for: operation) else {
        await invalid(operationID, coordinator: coordinator)
        return
      }
      try? await coordinator.prerequisitesComplete(operationID: operationID)
    }

    /// Takes the PIN an action needs: the held PIN 1 with no prompt, or the
    /// holder's entry on a prompt; reads never come here (§8.2 items 3 and
    /// 6).
    internal func handleApproval(
      operationID: RappOperationIdentifier,
      operation: RappOperationDriver.Operation,
      coordinator: RappConnectionCoordinator
    ) async {
      guard let action = action(for: operation.kind) else {
        #if DEBUG
          HolderTrace.say("handleApproval: no PIN defined for \(operation.kind)")
        #endif
        await invalid(operationID, coordinator: coordinator)
        return
      }
      if await takeHeldPin1(operationID: operationID, operation: operation) {
        try? await coordinator.approve(operationID: operationID)
        return
      }
      #if DEBUG
        HolderTrace.say("handleApproval: asking holder for the PIN for \(operation.kind)")
      #endif
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

    /// Shows the PIN prompt for the operation and waits for the holder.
    ///
    /// The requester hears `consent_shown` once the operation's first prompt
    /// is on screen (§8.2 item 3). A `notice` says why the holder is asked
    /// again for the same operation: the card refused the PIN entered last
    /// (§10.2).
    internal func ask(
      operationID: RappOperationIdentifier,
      operation: RappOperationDriver.Operation,
      action: RappAuthorizationRequest.Action,
      notice: String?,
      coordinator: RappConnectionCoordinator
    ) async -> RappAuthorizationDecision {
      let request = RappAuthorizationRequest(
        requestID: requestID(for: operationID),
        requester: requesterName,
        action: action,
        documentNames: Self.promptDocuments(for: operation),
        notice: notice
      )
      // A warm near field's system sheet would cover the prompt: the field
      // ends first, and the reader's pause after it runs while the holder
      // types.
      await RappNearFieldSessionHolder.shared.closeSession(.promptShown)
      if promptedOperations.insert(operationID).inserted {
        try? await coordinator.reportProgress(operationID: operationID, event: .consentShown)
      }
      return await inbox.ask(request)
    }

    /// Spends the PIN 1 the phone holds on a browser authentication, with no
    /// prompt (§11 item 2); false when none is held or the action needs
    /// PIN 2.
    private func takeHeldPin1(
      operationID: RappOperationIdentifier,
      operation: RappOperationDriver.Operation
    ) async -> Bool {
      guard operation.kind == .browserAuthenticate,
        let held = await MainActor.run(body: {
          HeldPin1.shared.current(card: PhonePersistentTokenRelay.shared.servedCardFingerprint)
        })
      else { return false }
      #if DEBUG
        HolderTrace.say("handleApproval: using held PIN 1")
      #endif
      pin1ByOperation[operationID] = .heldPin1(held)
      return true
    }

    /// Takes the holder's decision: a denial ends the operation, an approval
    /// holds the PIN entered for the card command.
    internal func resolveApprovalDecision(
      _ decision: RappAuthorizationDecision,
      operationID: RappOperationIdentifier,
      operation: RappOperationDriver.Operation,
      coordinator: RappConnectionCoordinator
    ) async {
      guard acceptDecision(decision, operationID: operationID, operation: operation) else {
        try? await coordinator.deny(operationID: operationID)
        return
      }
      try? await coordinator.approve(operationID: operationID)
    }

    /// Keeps the PIN an approval carries for the operation's card command.
    ///
    /// False for a denial or a PIN of the wrong kind. PIN 1 is held beyond
    /// the operation only once the card accepts it.
    internal func acceptDecision(
      _ decision: RappAuthorizationDecision,
      operationID: RappOperationIdentifier,
      operation: RappOperationDriver.Operation
    ) -> Bool {
      switch decision {
      case .approvedBrowserAuthentication(let pin1):
        guard operation.kind == .browserAuthenticate else { return false }
        pin1ByOperation[operationID] = .enteredPin1(pin1.digits)
        return true

      case .approvedDocumentSignature(let pin2):
        guard operation.kind == .signDocument || operation.kind == .batchSignDocuments else {
          return false
        }
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
  }

#endif
