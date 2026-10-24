// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Testing

@testable import RefineIDTestHost

/// When a card command summons the holder before it runs (STPA CC-69).
@Suite
internal struct HolderAttentionTests {
  private static let appStates: [HolderAttention.AppState] = [.active, .inactive, .background]
  private static let fieldStates = [true, false]

  @Test("A reader card is commanded without the holder, whatever the app does")
  internal func readerNeedsNoScreen() {
    for app in Self.appStates {
      for fieldWarm in Self.fieldStates {
        #expect(HolderAttention.needed(for: .reader, app: app, fieldWarm: fieldWarm) == .proceed)
      }
    }
  }

  @Test("The near-field card from the background summons the holder, warm field or not")
  internal func nearFieldFromTheBackgroundSummons() {
    for fieldWarm in Self.fieldStates {
      #expect(
        HolderAttention.needed(for: .nearField, app: .background, fieldWarm: fieldWarm)
          == .summon)
    }
  }

  @Test("The near-field card in the foreground is commanded at once")
  internal func nearFieldInTheForegroundProceeds() {
    for fieldWarm in Self.fieldStates {
      #expect(
        HolderAttention.needed(for: .nearField, app: .active, fieldWarm: fieldWarm)
          == .proceed)
    }
  }

  @Test("A warm near field under its system sheet is commanded without a summons")
  internal func warmFieldUnderItsSheetProceeds() {
    #expect(HolderAttention.needed(for: .nearField, app: .inactive, fieldWarm: true) == .proceed)
  }

  @Test("An inactive app without a warm near field summons the holder")
  internal func inactiveWithoutWarmFieldSummons() {
    #expect(HolderAttention.needed(for: .nearField, app: .inactive, fieldWarm: false) == .summon)
  }
}
