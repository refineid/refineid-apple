// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

extension CardCredentialsView {
  // MARK: - Type Methods

  nonisolated private static func extractPortraitBytes(from operations: CardOperations) -> Data? {
    try? operations.selectTravelDocumentApplication()
    guard let inventory = try? operations.readDataGroupInventory(),
      inventory.carriesDisplayedPortrait
    else {
      return nil
    }
    return try? operations.readDisplayedPortrait(listedBy: inventory)?.bytes
  }

  // MARK: - Instance Methods

  /// Reads the card photo for the identity submenu from reader or contactless card,
  /// falling back to demonstration or synthetic samples.
  @MainActor
  internal func readCardPhoto(for requestedHolder: String?) async -> Data? {
    #if os(iOS)
      let holder = requestedHolder ?? identityHolder ?? readerHolders.first ?? ""
    #else
      let holder = requestedHolder ?? identityHolder ?? ""
    #endif
    guard !holder.isEmpty else { return nil }
    #if os(iOS)
      if isDemonstration {
        let sample = CardPhotoStore.syntheticSamplePhoto(name: holder)
        CardPhotoStore.savePhoto(sample, for: holder)
        return sample
      }
    #endif
    #if REFINEID_LOCAL_CARD && os(iOS)
      if let answer = await CardMaintenance.onReaderCard(
        cardAccessNumber: cardAccessNumberEntry.isEmpty ? nil : cardAccessNumberEntry,
        Self.extractPortraitBytes
      ) {
        if case .connected(let bytes) = answer, let bytes {
          CardPhotoStore.savePhoto(bytes, for: holder)
          return bytes
        }
      }
      if offersNearField {
        let can = registrationCardAccessNumber() ?? cardAccessNumberEntry
        if !can.isEmpty {
          let answer = await CardMaintenance.onSecureNearFieldCard(
            cardAccessNumber: can,
            message: CardPriming.holdMessage,
            Self.extractPortraitBytes
          )
          if case .connected(let bytes) = answer, let bytes {
            CardPhotoStore.savePhoto(bytes, for: holder)
            return bytes
          }
        }
      }
    #endif
    #if DEBUG
      let sample = CardPhotoStore.syntheticSamplePhoto(name: holder)
      CardPhotoStore.savePhoto(sample, for: holder)
      return sample
    #else
      return nil
    #endif
  }

  @MainActor
  internal func readCardPhoto() async -> Data? {
    await readCardPhoto(for: nil)
  }
}
