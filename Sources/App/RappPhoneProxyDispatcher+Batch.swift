// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation

  /// `batch_sign_documents` on the custodian (RAPP v26.10.9 §9.3).
  extension RappPhoneProxyDispatcher {
    /// Signs every document of an approved batch in one card session with
    /// the one PIN 2 the holder entered, journaling each signature before
    /// the next document.
    ///
    /// A batch interrupted after any signature is ambiguous and carries the
    /// signatures already made; one that fails before the first ends as the
    /// single-document path would.
    internal func executeBatch(
      operationID: Data,
      operation: RappOperationDriver.Operation,
      accessNumber: String?,
      coordinator: RappConnectionCoordinator
    ) async {
      guard let keyProfile = operation.keyProfile, let algorithm = operation.algorithm,
        let pin2 = pin2ByOperation.removeValue(forKey: operationID),
        let recorder = try? await coordinator.batchSignatureRecorder(operationID: operationID)
      else {
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
      } else if batch.signed > 0 {
        await requireExplicitReconnect()
        try? await coordinator.cardCompletionAmbiguous(operationID: operationID)
      } else {
        await finishFailure(batch.outcome, operationID: operationID, coordinator: coordinator)
      }
    }
  }
#endif
