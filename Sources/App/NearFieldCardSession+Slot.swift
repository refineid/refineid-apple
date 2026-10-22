// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CryptoTokenKit
  import Foundation

  /// Asking `nfcd` for the slot.
  extension NearFieldCardSession {
    /// Asks for the slot through the busy radio and the reader's pause
    /// after a field (``NearFieldSlotRequest``).
    internal static func openSlot(
      manager: TKSmartCardSlotManager,
      message: String
    ) async throws -> TKSmartCardSlotNFCSession {
      let answer = await NearFieldSlotRequest.request(
        attempt: { await createSlot(manager: manager, message: message) },
        pause: { interval in try? await Task.sleep(for: interval) }
      )
      switch answer {
      case .success(let opened):
        return opened

      case .failure(.busy):
        throw Failure.antennaBusy

      case .failure(.cancelled):
        throw Failure.dismissed

      case .failure(.readerPaused):
        throw Failure.readerCoolingDown

      case .failure(.refused):
        throw Failure.slotRefused
      }
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
  }
#endif
