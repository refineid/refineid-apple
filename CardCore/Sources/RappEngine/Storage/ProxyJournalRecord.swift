// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

internal let proxyJournalFormatVersion: UInt64 = 1

/// Proxy's durable record of one operation, carrying the transmission count
/// that makes a card command at most once.
internal struct ProxyJournalRecord: Equatable {
  /// How far a batch got.
  ///
  /// Its size and the signatures already made, in order; the next document
  /// to sign is at `completedSignatures.count`.
  internal struct BatchProgress: Equatable {
    internal var total: Int
    internal var completedSignatures: [Data]

    internal var activeIndex: Int { completedSignatures.count }

    fileprivate var value: WireValue {
      .map([
        "batch_total": .unsigned(UInt64(total)),
        "completed_signatures": .array(completedSignatures.map(WireValue.bytes)),
        "index": .unsigned(UInt64(activeIndex)),
      ])
    }

    fileprivate static func from(_ value: WireValue) throws -> Self {
      guard case .map(var map) = value else { throw PairRecordError.invalidInput }
      let declaredTotal = try takeUnsigned(&map, "batch_total")
      guard case .array(let values)? = map.removeValue(forKey: "completed_signatures") else {
        throw PairRecordError.invalidInput
      }
      let completed = try values.map { element in
        guard case .bytes(let signature) = element, !signature.isEmpty else {
          throw PairRecordError.invalidInput
        }
        return signature
      }
      let declaredIndex = try takeUnsigned(&map, "index")
      guard map.isEmpty, let size = Int(exactly: declaredTotal), size > 0,
        completed.count <= size, declaredIndex == UInt64(completed.count)
      else { throw PairRecordError.invalidInput }
      return Self(total: size, completedSignatures: completed)
    }
  }

  internal var pairIdentifier: Data
  internal var sessionIdentifier: Data
  internal var operationIdentifier: Data
  internal var requestHash: Data
  internal var state: OperationState
  internal var transmissionCount: UInt8
  internal var automaticRetryPermitted: Bool
  /// A batch's per-document progress (RAPP v26.10.1 §8.1, §9.3); nil for
  /// every other operation.
  internal var batch: BatchProgress?

  internal static func decode(_ bytes: Data) throws -> Self {
    var map = try decodedMap(bytes)
    guard try takeUnsigned(&map, "format_version") == proxyJournalFormatVersion else {
      throw PairRecordError.invalidInput
    }
    let decodedPairIdentifier = try takeBytes(&map, "pair_id")
    let decodedSessionIdentifier = try takeBytes(&map, "session_id")
    let decodedOperationIdentifier = try takeBytes(&map, "operation_id")
    let decodedRequestHash = try takeBytes(&map, "request_hash")
    guard decodedPairIdentifier.count == PairRecordSize.pairIdentifier,
      decodedSessionIdentifier.count == JournalSize.sessionIdentifier,
      decodedOperationIdentifier.count == JournalSize.operationIdentifier,
      decodedRequestHash.count == JournalSize.requestHash
    else { throw PairRecordError.invalidInput }
    guard let decodedState = OperationState(rawValue: try takeText(&map, "state")) else {
      throw PairRecordError.invalidInput
    }
    let transmissions = try takeUnsigned(&map, "transmission_count")
    guard let decodedTransmissionCount = UInt8(exactly: transmissions)
    else { throw PairRecordError.invalidInput }
    let decodedAutomaticRetryPermitted = try takeBoolean(&map, "automatic_retry_permitted")
    let decodedBatch = try map.removeValue(forKey: "batch").map(BatchProgress.from)
    guard map.isEmpty else { throw PairRecordError.invalidInput }
    return Self(
      pairIdentifier: decodedPairIdentifier,
      sessionIdentifier: decodedSessionIdentifier,
      operationIdentifier: decodedOperationIdentifier,
      requestHash: decodedRequestHash,
      state: decodedState,
      transmissionCount: decodedTransmissionCount,
      automaticRetryPermitted: decodedAutomaticRetryPermitted,
      batch: decodedBatch
    )
  }

  internal func encoded() throws -> Data {
    var map: [String: WireValue] = [
      "format_version": .unsigned(proxyJournalFormatVersion),
      "pair_id": .bytes(pairIdentifier),
      "session_id": .bytes(sessionIdentifier),
      "operation_id": .bytes(operationIdentifier),
      "request_hash": .bytes(requestHash),
      "state": .text(state.rawValue),
      "transmission_count": .unsigned(UInt64(transmissionCount)),
      "automatic_retry_permitted": .boolean(automaticRetryPermitted),
    ]
    if let batch {
      map["batch"] = batch.value
    }
    do {
      return try WireValue.map(map).encoded()
    } catch {
      throw PairRecordError.invalidInput
    }
  }
}
