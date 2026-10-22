// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// Records a batch's signatures from inside one synchronous card session
  /// (RAPP v26.10.22 §9.3), so the batch completes with exactly the
  /// signatures the card made, one per document.
  public final class RappBatchSignatureRecorder: Sendable {
    private let bridge: RappOperationBridge
    private let operationID: RappOperationIdentifier

    internal init(bridge: RappOperationBridge, operationID: RappOperationIdentifier) {
      self.bridge = bridge
      self.operationID = operationID
    }

    /// Records one signature; false means the batch can no longer complete
    /// and must stop before the next document.
    public func record(_ signature: Data) -> Bool {
      (try? bridge.recordBatchSignature(operationId: operationID, signature: signature)) != nil
    }
  }
#endif
