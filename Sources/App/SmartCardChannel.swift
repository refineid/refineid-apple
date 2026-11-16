// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoTokenKit
import Foundation

/// App-side wait policy and trace wiring for ``SmartCardChannel``.
extension SmartCardChannel {
  /// How long one APDU may wait, set by the transport that owns the field.
  internal enum ResponseWait: Equatable, Sendable {
    case nearField
    case nearFieldRecovery
    case reader
  }

  /// Session wait budget for status and priming reads: short enough that a card
  /// busy signing for another client reports contention instead of stalling the UI.
  private static let sessionWaitSeconds = 4

  /// Maximum time allowed for an individual APDU response on near-field.
  internal static let nearFieldResponseSeconds = 10

  /// Maximum time allowed for an individual APDU response on near-field during recovery.
  ///
  /// Accommodates card anti-tamper penalty delays (FIA_AFL.1/PACE, typically 40-45+ seconds)
  /// within the ceiling of the system NFC slot session.
  internal static let nearFieldRecoveryResponseSeconds = 50

  /// Reader response budget accommodating progressive CAN-PACE delays and on-card crypto.
  internal static let readerResponseSeconds = 60

  private static var appTraceSink: TraceSink {
    #if DEBUG
      TraceSink(
        exchange: { record in
          AppTrace.append(record.line)
        },
        trace: nil,
        error: nil
      )
    #else
      .silent
    #endif
  }

  internal init(_ smartCard: TKSmartCard, waits: ResponseWait) {
    self.init(
      smartCard,
      policy: Self.waitPolicy(for: waits),
      trace: Self.appTraceSink
    )
  }

  internal init(_ smartCard: TKSmartCard) {
    self.init(
      smartCard,
      waits: Self.defaultWait(forSlotNamed: smartCard.slot.name)
    )
  }

  /// Determines the appropriate wait policy for a given smart card slot name.
  internal static func defaultWait(forSlotNamed name: String) -> ResponseWait {
    CardTransport.transport(forSlotNamed: name) == .nearField ? .nearField : .reader
  }

  private static func waitPolicy(for waits: ResponseWait) -> WaitPolicy {
    let sessionBudget = DispatchTimeInterval.seconds(Self.sessionWaitSeconds)
    switch waits {
    case .nearField:
      return WaitPolicy(
        sessionWait: sessionBudget,
        responseWait: .seconds(Self.nearFieldResponseSeconds),
        signatureRoute: .raw
      )
    case .nearFieldRecovery:
      return WaitPolicy(
        sessionWait: sessionBudget,
        responseWait: .seconds(Self.nearFieldRecoveryResponseSeconds),
        signatureRoute: .raw
      )
    case .reader:
      return WaitPolicy(
        sessionWait: sessionBudget,
        responseWait: .seconds(Self.readerResponseSeconds),
        signatureRoute: .raw
      )
    }
  }
}
