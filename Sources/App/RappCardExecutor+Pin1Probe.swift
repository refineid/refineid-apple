// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation
  import os
  import RappEngine

  extension RappCardExecutor {
    private struct Pin1ProbeState {
      var card: RappCertificateFingerprint?
      var probe: RetryProbeOutcome?
      var pristineAllowance: UInt8 = RetryCount.pristineAllowance
    }

    /// Collects the pre-VERIFY PIN 1 probe and authenticated card identity
    /// observed during one browser authentication, while clearing
    /// ``HeldPin1`` immediately on any non-pristine probe or refusal.
    internal final class Pin1ProbeObserver: Sendable {
      private let recorded = OSAllocatedUnfairLock<Pin1ProbeState>(
        initialState: Pin1ProbeState()
      )

      internal var authenticatedCard: RappCertificateFingerprint? {
        recorded.withLock { $0.card }
      }

      internal var preVerifyProbe: RetryProbeOutcome? {
        recorded.withLock { $0.probe }
      }

      internal var pristineAllowance: UInt8 {
        recorded.withLock { $0.pristineAllowance }
      }

      internal func recordCard(_ certificateDER: Data) {
        let card = RappCertificateFingerprint(certificate: certificateDER)
        recorded.withLock { $0.card = card }
      }

      internal func recordProbe(_ probe: RetryProbeOutcome) {
        recordProbe(probe, pristineAllowance: RetryCount.pristineAllowance)
      }

      internal func recordProbe(
        _ probe: RetryProbeOutcome,
        pristineAllowance: UInt8
      ) {
        HeldPin1.shared.retain(after: probe, pristineAllowance: pristineAllowance)
        recorded.withLock { state in
          state.pristineAllowance = pristineAllowance
          if state.probe == nil
            || !Pin1Retention.permitsHolding(after: probe, allowance: pristineAllowance)
          {
            state.probe = probe
          }
        }
      }

      internal func clearHeld() {
        HeldPin1.shared.clear()
      }
    }
  }
#endif
