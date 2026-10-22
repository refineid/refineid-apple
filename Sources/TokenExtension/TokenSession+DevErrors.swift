// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG
  import CryptoTokenKit
  import Foundation

  /// How a failed signature reaches the development error display.
  extension TokenSession {
    /// Records a signature the system asked for and did not get.
    ///
    /// A request for the PIN is how a signature begins, not a failure, and
    /// is not recorded.
    internal static func reportSignFailure(_ error: any Error, milliseconds: String) {
      if let tokenError = error as? TKError, tokenError.code == .authenticationNeeded {
        return
      }
      DevErrorLog.report(
        "sign failed after \(milliseconds) ms: \(DevErrorLog.reason(error))",
        source: .tokenExtension)
    }
  }
#endif
