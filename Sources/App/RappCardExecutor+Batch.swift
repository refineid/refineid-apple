// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation

  /// `batch_sign_documents` at the card (RAPP v26.10.9 §9.3).
  extension RappCardExecutor {
    /// How far a batch got: the signatures journaled, and the outcome that
    /// ended it.
    internal struct BatchOutcome: Sendable {
      internal let signed: Int
      internal let outcome: Outcome
    }

    /// Counts journaled batch signatures across the card session.
    private final class BatchCounter: @unchecked Sendable {
      private let lock = NSLock()
      private var count = 0

      var signed: Int { lock.withLock { count } }

      func increment() { lock.withLock { count += 1 } }
    }

    /// What a batch signs: one key and algorithm over every digest, in order.
    internal struct BatchRequest: Sendable {
      internal let keyProfile: RappOperationDriver.KeyProfile
      internal let algorithm: RappOperationDriver.SignatureAlgorithm
      internal let digests: [Data]
    }

    /// Signs each digest in order in one card session, verifying the held
    /// PIN 2 before each qualified signature, and journals every signature
    /// through `recorder` before the next document.
    internal static func signDocuments(
      cardAccessNumber: String?,
      pin2: String,
      request: BatchRequest,
      recorder: RappBatchSignatureRecorder
    ) async -> BatchOutcome {
      let counter = BatchCounter()
      let outcome = await withCard(cardAccessNumber: cardAccessNumber) { operations, context in
        for digest in request.digests {
          let outcome = executeSign(
            SignParameters(
              cardAccessNumber: cardAccessNumber,
              documentPin1: nil,
              documentPin2: pin2,
              role: .pin2,
              slot: .qualifiedSignature,
              keyProfile: request.keyProfile,
              algorithm: request.algorithm,
              digest: digest,
              qualified: true),
            with: operations, context: context)
          guard case .result(let signature) = outcome else { return outcome }
          guard recorder.record(signature) else { return .completionAmbiguous }
          counter.increment()
        }
        return .result(Data())
      }
      return BatchOutcome(signed: counter.signed, outcome: outcome)
    }
  }
#endif
