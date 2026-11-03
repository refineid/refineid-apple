// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation

  /// `batch_sign_documents` at the card (RAPP v26.11.2 §9.3).
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
      pin2: Pin2Entry,
      request: BatchRequest,
      recorder: RappBatchSignatureRecorder
    ) async -> BatchOutcome {
      let counter = BatchCounter()
      let parameters = request.digests.map { digest in
        SignParameters(
          cardAccessNumber: cardAccessNumber,
          pin: .pin2(pin2),
          keyProfile: request.keyProfile,
          algorithm: request.algorithm,
          digest: digest)
      }
      // An organization card's PIN 2 opens one channel for one signature,
      // so each document runs its own PACE with the same entry.
      let outcome = await withCard(
        cardAccessNumber: cardAccessNumber,
        operation: .signature,
        organization: { plain, context in
          signEach(parameters, counter: counter, recorder: recorder) { params in
            executeOrganizationSign(params, on: plain, context: context)
          }
        },
        personal: { operations, context in
          signEach(parameters, counter: counter, recorder: recorder) { params in
            executeSign(params, with: operations, context: context)
          }
        }
      )
      return BatchOutcome(signed: counter.signed, outcome: outcome)
    }

    /// Signs each document in order, journaling every signature before
    /// the next; the first outcome without a signature ends the batch.
    private static func signEach(
      _ parameters: [SignParameters],
      counter: BatchCounter,
      recorder: RappBatchSignatureRecorder,
      _ signOne: (SignParameters) -> Outcome
    ) -> Outcome {
      for params in parameters {
        let outcome = signOne(params)
        guard case .result(let signature) = outcome else { return outcome }
        guard recorder.record(signature) else { return .completionAmbiguous }
        counter.increment()
      }
      return .result(Data())
    }
  }
#endif
