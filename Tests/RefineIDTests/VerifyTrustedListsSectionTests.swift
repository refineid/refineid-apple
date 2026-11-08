// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Testing

@testable import RefineIDTestHost

/// The trusted lists are fetched in the background and shown only when
/// a failed fetch leaves verification without current lists.
@Suite
internal struct VerifyTrustedListsSectionTests {
  @Test
  internal func currentListsShowNothingEvenAfterAFailedRefresh() {
    #expect(!VerifyTrustedListsSection.needsAttention(failed: false, stored: true, stale: false))
    #expect(!VerifyTrustedListsSection.needsAttention(failed: true, stored: true, stale: false))
  }

  @Test
  internal func aFailedFetchWithNoListsOrStaleOnesIsShown() {
    #expect(VerifyTrustedListsSection.needsAttention(failed: true, stored: false, stale: false))
    #expect(VerifyTrustedListsSection.needsAttention(failed: true, stored: true, stale: true))
  }

  @Test
  internal func nothingIsShownWhileNoFetchHasFailed() {
    #expect(!VerifyTrustedListsSection.needsAttention(failed: false, stored: false, stale: false))
    #expect(!VerifyTrustedListsSection.needsAttention(failed: false, stored: true, stale: true))
  }
}
