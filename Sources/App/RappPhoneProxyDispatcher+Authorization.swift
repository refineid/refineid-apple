// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)

  import CardCore
  import Foundation

  /// Authorization handling and approval resolution for remote proxy operations.
  extension RappPhoneProxyDispatcher {
    /// What the holder is shown: the origin or document name, or a batch's
    /// whole document list in signing order (RAPP v26.10.1 §9.3).
    private static func consentContext(for operation: RappOperationDriver.Operation) -> String? {
      guard operation.kind == .batchSignDocuments else { return operation.displayContext }
      return operation.documentNames.joined(separator: "\n")
    }

    internal func inspectPrerequisites(
      operationID: Data,
      operation: RappOperationDriver.Operation,
      coordinator: RappConnectionCoordinator
    ) async {
      guard prerequisitesExist(for: operation) else {
        try? await coordinator.requestInvalidOrUnsupported(operationID: operationID)
        return
      }
      try? await coordinator.prerequisitesComplete(operationID: operationID)
    }

    internal func handleApproval(
      operationID: Data,
      operation: RappOperationDriver.Operation,
      coordinator: RappConnectionCoordinator
    ) async {
      #if DEBUG
        HolderTrace.say(
          "handleApproval: kind=\(operation.kind), isSafeRead=\(operation.kind.isSafeRead)"
        )
      #endif
      guard let action = action(for: operation.kind) else {
        #if DEBUG
          HolderTrace.say(
            "handleApproval: rejected because no action mapping for \(operation.kind)"
          )
        #endif
        try? await coordinator.requestInvalidOrUnsupported(operationID: operationID)
        return
      }
      if await tryAutoApprove(operationID: operationID, operation: operation) {
        try? await coordinator.approve(operationID: operationID)
        return
      }
      let request = RappAuthorizationRequest(
        requestID: operationID.base64EncodedString(),
        requester: await Self.requesterName()
          ?? String(localized: "Paired device"),
        action: action,
        displayContext: Self.consentContext(for: operation)
      )
      #if DEBUG
        HolderTrace.say("handleApproval: asking holder authorization for \(operation.kind)")
      #endif
      let decision = await inbox.ask(request)
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

    private func tryAutoApprove(
      operationID: Data,
      operation: RappOperationDriver.Operation
    ) async -> Bool {
      if operation.kind.isSafeRead {
        #if DEBUG
          HolderTrace.say("handleApproval: safe read auto-approved")
        #endif
        return true
      }
      if operation.kind == .browserAuthenticate {
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
      }
      return false
    }

    private func resolveApprovalDecision(
      _ decision: RappAuthorizationDecision,
      operationID: Data,
      operation: RappOperationDriver.Operation,
      coordinator: RappConnectionCoordinator
    ) async {
      #if DEBUG
        HolderTrace.say("resolveApprovalDecision: \(decision.summary) for \(operation.kind)")
      #endif
      switch decision {
      case .approved:
        try? await coordinator.approve(operationID: operationID)

      case .approvedBrowserAuthentication(let pin1):
        guard operation.kind == .browserAuthenticate else {
          try? await coordinator.requestInvalidOrUnsupported(operationID: operationID)
          return
        }
        pin1ByOperation[operationID] = pin1.digits
        let isReader = await MainActor.run { CardPresence.shared.isReaderCardPresent }
        if isReader {
          await rememberReaderPin1(pin1.digits)
        }
        try? await coordinator.approve(operationID: operationID)

      case .approvedDocumentSignature(let pin2):
        guard operation.kind == .signDocument || operation.kind == .batchSignDocuments else {
          try? await coordinator.requestInvalidOrUnsupported(operationID: operationID)
          return
        }
        pin2Window.hold(pin2.digits)
        pin2ByOperation[operationID] = pin2.digits
        try? await coordinator.approve(operationID: operationID)

      case .denied:
        try? await coordinator.deny(operationID: operationID)
      }
    }

    private func prerequisitesExist(
      for operation: RappOperationDriver.Operation
    ) -> Bool {
      switch operation.kind {
      case .inspectCard, .readIdentity, .readAuthenticationCertificate,
        .readSignatureCertificate, .readRootCertificate, .readIntermediateCertificate:
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

    private func action(
      for kind: RappOperationDriver.OperationKind
    ) -> RappAuthorizationRequest.Action? {
      switch kind {
      case .browserAuthenticate:
        .browserAuthentication

      case .signDocument, .batchSignDocuments:
        .documentSignature

      case .inspectCard, .readIdentity, .readAuthenticationCertificate,
        .readSignatureCertificate, .readRootCertificate, .readIntermediateCertificate:
        .shareCardInformation
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
