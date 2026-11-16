// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoTokenKit
import Foundation

/// Token-extension wait policy and trace wiring for ``SmartCardChannel``.
extension SmartCardChannel {
  /// Transport wait profile for token creation and signing inside `ctkd`.
  internal enum ResponseWait: Equatable, Sendable {
    case nearField
    case reader
    case readerMint
  }

  private static let nearFieldSessionWaitSeconds = 10
  private static let readerMintSessionWaitSeconds = 8
  private static let readerSessionWaitSeconds = 60
  private static let nearFieldResponseSeconds = 10
  private static let readerResponseSeconds = 60

  private static var extensionTraceSink: TraceSink {
    #if DEBUG
      TraceSink(
        exchange: { record in
          TokenLog.trace(
            "\(record.line) channel=\(record.channelID) \(record.progressSnapshot)"
          )
        },
        trace: { line in
          TokenLog.trace(line)
        },
        error: { line in
          TokenLog.error(line)
        }
      )
    #else
      .silent
    #endif
  }

  internal init(_ smartCard: TKSmartCard, waits: ResponseWait) {
    self.init(
      smartCard,
      policy: Self.waitPolicy(for: waits),
      trace: Self.extensionTraceSink
    )
  }

  private static func waitPolicy(for waits: ResponseWait) -> WaitPolicy {
    switch waits {
    case .nearField:
      return WaitPolicy(
        sessionWait: .seconds(Self.nearFieldSessionWaitSeconds),
        responseWait: .seconds(Self.nearFieldResponseSeconds),
        signatureRoute: .structured
      )
    case .reader:
      return WaitPolicy(
        sessionWait: .seconds(Self.readerSessionWaitSeconds),
        responseWait: .seconds(Self.readerResponseSeconds),
        signatureRoute: .raw
      )
    case .readerMint:
      return WaitPolicy(
        sessionWait: .seconds(Self.readerMintSessionWaitSeconds),
        responseWait: .seconds(Self.readerResponseSeconds),
        signatureRoute: .raw
      )
    }
  }
}
