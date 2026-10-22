// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Testing

@testable import RefineID

/// When a card command summons the holder before it runs (STPA CC-69).
@Suite
internal struct HolderAttentionTests {
  @Test("A reader card is commanded from the background without the holder")
  internal func readerNeedsNoScreen() {
    #expect(HolderAttention.needed(for: .reader, appActive: false) == .proceed)
    #expect(HolderAttention.needed(for: .reader, appActive: true) == .proceed)
  }

  @Test("The near-field card from the background summons the holder")
  internal func nearFieldFromTheBackgroundSummons() {
    #expect(HolderAttention.needed(for: .nearField, appActive: false) == .summon)
  }

  @Test("The near-field card in the foreground is commanded at once")
  internal func nearFieldInTheForegroundProceeds() {
    #expect(HolderAttention.needed(for: .nearField, appActive: true) == .proceed)
  }
}
