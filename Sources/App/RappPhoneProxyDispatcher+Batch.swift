// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation
  import RappEngine

  /// `batch_sign_documents` on the custodian (RAPP v26.10.21 §9.3).
  extension RappPhoneProxyDispatcher {
    /// Signs every document of an approved batch in one card session with
    /// the one PIN 2 the holder entered, and answers with every signature
    /// or with why it could not.
    ///
    /// A PIN 2 the card refuses before the first signature is asked for
    /// again while the retry floor allows (§10.2). A batch that stops after
    /// any signature ends with the card's error: no signature of an
    /// interrupted batch is delivered.
    internal func executeBatch(
      operationID: RappOperationIdentifier,
      operation: RappOperationDriver.Operation,
      accessNumber: String?,
      coordinator: RappConnectionCoordinator
    ) async {
      guard let keyProfile = operation.keyProfile, let algorithm = operation.algorithm,
        let recorder = try? await coordinator.batchSignatureRecorder(operationID: operationID)
      else {
        await invalid(operationID, coordinator: coordinator)
        return
      }
      while true {
        guard let pin2 = pin2ByOperation.removeValue(forKey: operationID) else {
          await invalid(operationID, coordinator: coordinator)
          return
        }
        let batch = await RappCardExecutor.signDocuments(
          cardAccessNumber: accessNumber,
          pin2: pin2,
          request: RappCardExecutor.BatchRequest(
            keyProfile: keyProfile, algorithm: algorithm, digests: operation.digests),
          recorder: recorder)
        if batch.signed == operation.digests.count {
          try? await coordinator.completeBatch(operationID: operationID)
          return
        }
        if batch.signed > 0 {
          try? await coordinator.cardError(operationID: operationID)
          return
        }
        switch await askAgainAfterRefusedPin(
          batch.outcome, operationID: operationID, operation: operation,
          coordinator: coordinator)
        {
        case .askedAgain:
          continue

        case .declined:
          return

        case .outcomeStands:
          await finishFailure(batch.outcome, operationID: operationID, coordinator: coordinator)
          return
        }
      }
    }
  }
#endif
