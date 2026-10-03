// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import SwiftUI
import Testing

@testable import RefineID

@Suite
internal struct CardIdentityViewTests {
  private static let maxPersonNameLength = 54
  private static let photoDataMinByteCount = 100

  @Test
  @MainActor
  internal func cardPhotoStoreSavesAndRetrievesPhoto() {
    let holder = "MÖTTÖNEN-KUMPULAINEN-AALTONEN VELI-MATTI-ANTERO-KALEVI"
    #expect(holder.count == Self.maxPersonNameLength)

    CardPhotoStore.deletePhoto(for: holder)
    #expect(CardPhotoStore.getPhoto(for: holder) == nil)

    let sample = CardPhotoStore.syntheticSamplePhoto(name: holder)
    #expect(sample.count > Self.photoDataMinByteCount)

    CardPhotoStore.savePhoto(sample, for: holder)
    #expect(CardPhotoStore.getPhoto(for: holder) == sample)

    CardPhotoStore.deletePhoto(for: holder)
    #expect(CardPhotoStore.getPhoto(for: holder) == nil)
  }

  @Test
  @MainActor
  internal func fiftyFourCharacterNameInCardIdentitySection() {
    let longName = "MÖTTÖNEN-KUMPULAINEN-AALTONEN VELI-MATTI-ANTERO-KALEVI"
    #expect(longName.count == Self.maxPersonNameLength)

    let section = CardIdentitySection(holder: longName)
    _ = section.body
    #expect(section.holder == longName)
  }

  #if REFINEID_LOCAL_CARD && os(iOS)
    @Test
    @MainActor
    internal func fiftyFourCharacterNameInCardReaderIdentitySection() {
      let longName = "MÖTTÖNEN-KUMPULAINEN-AALTONEN VELI-MATTI-ANTERO-KALEVI"
      #expect(longName.count == Self.maxPersonNameLength)

      let section = CardReaderIdentitySection(holders: [longName])
      _ = section.body
      #expect(section.holders.first == longName)
    }
  #endif

  @Test
  @MainActor
  internal func identitySubmenuViewInitializesWithFiftyFourCharacterName() {
    let longName = "MÖTTÖNEN-KUMPULAINEN-AALTONEN VELI-MATTI-ANTERO-KALEVI"
    var didForget = false
    let submenu = CardIdentitySubmenuView(
      holder: longName,
      identifier: "12345678A",
      onForget: {
        didForget = true
      },
      onReadPhoto: { _ in
        .success(CardPhotoStore.syntheticSamplePhoto(name: longName))
      }
    )
    _ = submenu.body
    submenu.onForget?()
    #expect(didForget)
  }

  @Test
  @MainActor
  internal func rappPairingViewRendersCardRemoteAccess() {
    let pairingView = RappPairingView()
    _ = pairingView.body
  }

  @Test
  @MainActor
  internal func cardIdentityPhotoViewRenders() {
    let longName = "MÖTTÖNEN-KUMPULAINEN-AALTONEN VELI-MATTI-ANTERO-KALEVI"
    let photoView = CardIdentityPhotoView(
      holder: longName,
      onReadPhoto: { _ in
        .cardAccessNumberRequired
      }
    )
    _ = photoView.body
  }

  @Test
  @MainActor
  internal func cardIdentityPhotoPlaceholderViewRenders() {
    let longName = "MÖTTÖNEN-KUMPULAINEN-AALTONEN VELI-MATTI-ANTERO-KALEVI"
    let idlePlaceholder = CardIdentityPhotoPlaceholderView(holder: longName, isReadingPhoto: false)
    _ = idlePlaceholder.body
    let loadingPlaceholder = CardIdentityPhotoPlaceholderView(
      holder: longName, isReadingPhoto: true)
    _ = loadingPlaceholder.body
  }
}
