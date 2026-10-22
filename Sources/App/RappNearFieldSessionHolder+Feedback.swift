// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import Foundation

  /// What the holder tells the person at the phone, the trace and the
  /// development error display about the field.
  extension RappNearFieldSessionHolder {
    /// Turns one field event into sounds, haptics and, in a development
    /// build, a trace line and an error display entry.
    ///
    /// The sounds go through the main queue in the order the field
    /// reported them, so an operation's outcome never sounds after the
    /// silence of the field's end.
    internal static func report(_ event: NearFieldEvent) {
      #if DEBUG
        trace(event)
      #endif
      switch event {
      case .operationStarted:
        onMain { CardPrimingFeedback.startWorking() }

      case .operationFinished(let succeeded):
        onMain { CardPrimingFeedback.report(succeeded: succeeded) }

      case .ended:
        OperationPhaseTrace.mark("session-ended")
        onMain { CardPrimingFeedback.stopWorking() }

      case .notOpened, .opened, .reused:
        break
      }
    }

    private static func onMain(_ body: @escaping @MainActor @Sendable () -> Void) {
      DispatchQueue.main.async {
        MainActor.assumeIsolated { body() }
      }
    }

    #if DEBUG
      /// Records the field's openings and endings with their causes; a
      /// burst of operations that reuses one field shows one of each.
      private static func trace(_ event: NearFieldEvent) {
        switch event {
        case .ended(let ending, let slotState):
          HolderTrace.say("near-field session ended: \(ending), slot \(slotState)")
          DevErrorLog.report(
            "near-field session ended: \(ending), slot \(slotState)", source: .app)

        case .notOpened(let failure):
          HolderTrace.say("near-field session not opened: \(failure)")
          DevErrorLog.report(
            "near-field session not opened: \(DevErrorLog.reason(failure))", source: .app)

        case .opened:
          HolderTrace.say("near-field session opened")
          DevErrorLog.report("near-field session opened", source: .app)

        case .reused:
          HolderTrace.say("near-field session reused")

        case .operationFinished, .operationStarted:
          break
        }
      }
    #endif
  }
#endif
