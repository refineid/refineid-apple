// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

extension CardCredentialsView {
  // MARK: - Types

  /// The outcome of reading a card photo from reader or contactless card.
  internal enum CardPhotoReadResult: Sendable {
    case success(Data)
    case wrongCardAccessNumber
    case cardAccessNumberRequired
    case cardUnavailable
    case failed
  }

  // MARK: - Instance Methods

  /// Reads the card photo for the identity submenu from reader or contactless card,
  /// using stored or entered CAN under PACE, falling back to demonstration samples only in demo mode.
  @MainActor
  internal func readCardPhoto(for requestedHolder: String?) async -> CardPhotoReadResult {
    await readCardPhoto(for: requestedHolder, accessNumber: nil)
  }

  @MainActor
  internal func readCardPhoto(
    for requestedHolder: String?,
    accessNumber: String?
  ) async -> CardPhotoReadResult {
    #if os(iOS)
      let holder =
        requestedHolder ?? identityHolder ?? selectedReaderHolder ?? readerHolders.first ?? ""
    #else
      let holder = requestedHolder ?? identityHolder ?? ""
    #endif
    guard !holder.isEmpty else { return .cardUnavailable }

    #if os(iOS)
      if isDemonstration {
        let sample = CardPhotoStore.syntheticSamplePhoto(name: holder)
        CardPhotoStore.savePhoto(sample, for: holder)
        return .success(sample)
      }
    #endif

    let canDigits =
      accessNumber
      ?? CardCredentialStore.displayedCardAccessNumber()
      ?? (isCardAccessNumberEntryComplete ? cardAccessNumberEntry : nil)

    guard let canDigits, let can = CardAccessNumber(digits: canDigits) else {
      return .cardAccessNumberRequired
    }

    let result = await CardMaintenance.onTravelDocumentCard(cardAccessNumber: can) {
      (operations: CardOperations) -> Data? in
      guard let inventory = try? operations.readDataGroupInventory(),
        inventory.carriesDisplayedPortrait,
        let portrait = try? operations.readDisplayedPortrait(listedBy: inventory)
      else {
        return nil
      }
      return portrait.bytes
    }

    switch result {
    case .success(let bytes):
      CardCredentialStore.save(cardAccessNumber: canDigits)
      CardPhotoStore.savePhoto(bytes, for: holder)
      return .success(bytes)

    case .wrongCardAccessNumber:
      CardCredentialStore.forgetCardAccessNumber()
      return .wrongCardAccessNumber

    case .cardUnavailable:
      return .cardUnavailable

    case .failed:
      return .failed
    }
  }

  @MainActor
  internal func readCardPhoto() async -> CardPhotoReadResult {
    await readCardPhoto(for: nil, accessNumber: nil)
  }

  @MainActor
  internal func readCardPhoto(accessNumber: String?) async -> CardPhotoReadResult {
    await readCardPhoto(for: nil, accessNumber: accessNumber)
  }
}
