// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CryptoTokenKit
  import Foundation

  /// Asking `nfcd` for the slot.
  extension NearFieldCardSession {
    /// How many times a busy radio is retried before giving up.
    internal static let busyRetryLimit: Int = 8

    /// Wait between two attempts at the radio.
    internal static let busyRetryInterval: Duration = .seconds(1)

    /// The word the system uses when `nfcd` still owns the radio.
    ///
    /// There is no error code for it, only the message, so this matches
    /// the message and treats everything else as a real refusal.
    internal static let busyErrorFragment: String = "busy"

    /// The refusal `nfcd` answers while its reader cool-off runs, observed
    /// as `Error Domain=nfcd Code=47 "Reader mode temporarily disabled"`.
    internal static let coolingDownErrorDomain: String = "nfcd"
    internal static let coolingDownErrorCode: Int = 47

    /// Asks for the slot, retrying only while the answer says busy.
    internal static func openSlot(
      manager: TKSmartCardSlotManager,
      message: String
    ) async throws -> TKSmartCardSlotNFCSession {
      var coolingDown = false
      for attempt in 1...Self.busyRetryLimit {
        if attempt > 1 {
          try? await Task.sleep(for: Self.busyRetryInterval)
        }
        switch await createSlot(manager: manager, message: message) {
        case .success(let opened):
          #if DEBUG
            if attempt > 1 { HolderTrace.say("openSlot: slot given on attempt \(attempt)") }
          #endif
          return opened

        case .failure(let error):
          #if DEBUG
            HolderTrace.say("openSlot: attempt \(attempt) refused: \(error)")
          #endif
          coolingDown = isCoolingDown(error)
          guard coolingDown || isBusy(error) else { throw Failure.slotRefused }
        }
      }
      throw coolingDown ? Failure.readerCoolingDown : Failure.antennaBusy
    }

    /// One call into `createNFCSlot`, as a value.
    internal static func createSlot(
      manager: TKSmartCardSlotManager,
      message: String
    ) async -> Result<TKSmartCardSlotNFCSession, any Error> {
      await withCheckedContinuation { continuation in
        manager.createNFCSlot(message: message) { opened, error in
          guard let opened else {
            continuation.resume(returning: .failure(error ?? Failure.slotRefused))
            return
          }
          continuation.resume(returning: .success(opened))
        }
      }
    }

    /// Whether this refusal is the reader cool-off, which no retry outlasts.
    internal static func isCoolingDown(_ error: any Error) -> Bool {
      let failure = error as NSError
      return failure.domain == Self.coolingDownErrorDomain
        && failure.code == Self.coolingDownErrorCode
    }

    /// Whether this refusal is the radio still being held elsewhere.
    internal static func isBusy(_ error: any Error) -> Bool {
      (error as NSError).localizedDescription
        .localizedCaseInsensitiveContains(Self.busyErrorFragment)
    }

  }
#endif
