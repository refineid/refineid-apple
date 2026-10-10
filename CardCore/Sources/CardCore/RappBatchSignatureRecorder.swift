// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// Journals a batch's signatures from inside one synchronous card session
  /// (RAPP v26.10.9 §8.1, §9.3).
  ///
  /// Each signature is durable before the card is asked for the next one,
  /// so an interruption delivers what was made and never makes it again.
  public final class RappBatchSignatureRecorder: Sendable {
    private let bridge: RappOperationBridge
    private let operationID: Data

    internal init(bridge: RappOperationBridge, operationID: Data) {
      self.bridge = bridge
      self.operationID = operationID
    }

    /// Records one signature; false means it is not durable and the batch
    /// must stop before the next document.
    public func record(_ signature: Data) -> Bool {
      (try? bridge.recordBatchSignature(operationId: operationID, signature: signature)) != nil
    }
  }
#endif
