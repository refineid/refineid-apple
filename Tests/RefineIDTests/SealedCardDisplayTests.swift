// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import RefineID

  /// The sealed-card section shows entry only when nothing is stored
  /// or the stored numbers just failed.
  @Suite
  internal struct SealedCardDisplayTests {
    @Test
    internal func offeringShowsInstruction() {
      #expect(
        SealedCardSection.display(
          offering: true, refused: false, refusedOnce: false, tryingStored: true)
          == .instruction)
    }

    @Test
    internal func refusalShowsEntry() {
      #expect(
        SealedCardSection.display(
          offering: false, refused: true, refusedOnce: false, tryingStored: true)
          == .entry)
    }

    @Test
    internal func earlierRefusalKeepsEntry() {
      #expect(
        SealedCardSection.display(
          offering: false, refused: false, refusedOnce: true, tryingStored: true)
          == .entry)
    }

    @Test
    internal func nothingStoredShowsEntry() {
      #expect(
        SealedCardSection.display(
          offering: false, refused: false, refusedOnce: false, tryingStored: false)
          == .entry)
    }

    @Test
    internal func storedNumberShowsTrying() {
      #expect(
        SealedCardSection.display(
          offering: false, refused: false, refusedOnce: false, tryingStored: true)
          == .trying)
    }
  }

#endif
