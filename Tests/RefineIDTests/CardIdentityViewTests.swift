// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import SwiftUI
import Testing

@testable import RefineID

@Suite
internal struct CardIdentityViewTests {
  private static let maxPersonNameLength = 54

  @Test
  @MainActor
  internal func fiftyFourCharacterNameInCardIdentitySection() {
    let longName = "MÖTTÖNEN-KUMPULAINEN-AALTONEN VELI-MATTI-ANTERO-KALEVI"
    #expect(longName.count == Self.maxPersonNameLength)

    var didRemove = false
    let section = CardIdentitySection(holder: longName) {
      didRemove = true
    }
    _ = section.body
    #expect(section.holder == longName)
    section.onRemove()
    #expect(didRemove)
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
  internal func rappPairingViewRendersCardRemoteAccess() {
    let pairingView = RappPairingView()
    _ = pairingView.body
  }
}
