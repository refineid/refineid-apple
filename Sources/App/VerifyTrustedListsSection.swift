// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// The trusted lists, shown only when fetching them failed in a way
/// that matters.
///
/// That is when none are stored, or the stored ones are stale. They
/// are fetched in the background; while that works there is nothing to
/// show.
internal struct VerifyTrustedListsSection: View {

  @ObservedObject internal var trustedLists: TrustedListStore

  internal var body: some View {
    if Self.needsAttention(
      failed: trustedLists.lastRefreshFailure != nil,
      stored: trustedLists.anchors?.fetchedAt != nil,
      stale: trustedLists.anchors?.isStale(at: Date()) ?? false
    ) {
      lists
    }
  }

  private var lists: some View {
    Section {
      VerifyDocumentRow(indicator: value.indicator) {
        Text(VerifyText.text("verify.trustedLists", "EU trusted lists"))
      } value: {
        if let line = value.line {
          Text(line)
            .accessibilityLabel(Text(verbatim: value.accessibilityLine))
        }
      }
      Button(VerifyText.text("verify.refreshTrustedLists", "Refresh EU trusted lists")) {
        Task { await trustedLists.refreshNow() }
      }
      .disabled(trustedLists.isRefreshing)
      .accessibilityIdentifier("verifyRefreshTrustedLists")
    }
  }

  /// Why the last fetch failed, as the row's secondary text.
  private var failureText: String? {
    switch trustedLists.lastRefreshFailure {
    case .offline:
      VerifyText.text("verify.trustedListsOffline", "Offline")

    case .unavailable:
      VerifyText.text("verify.trustedListsFetchFailed", "Fetch failed")

    case nil:
      nil
    }
  }

  /// The row: the fetch time, marked stale once a list is past its
  /// next update, or that nothing has been fetched; a failed fetch is
  /// the one error.
  private var value: VerifyDocumentRowValue {
    let failed = trustedLists.lastRefreshFailure != nil
    guard let anchors = trustedLists.anchors, let fetchedAt = anchors.fetchedAt else {
      return VerifyDocumentRowValue(
        text: VerifyText.text("verify.trustedListsNotFetched", "Not fetched"),
        secondaryText: failureText,
        indicator: trustedLists.isRefreshing ? .progress : failed ? .fails : .hidden
      )
    }
    let fetched = VerifyText.formatted(fetchedAt)
    let stale = anchors.isStale(at: Date())
    let secondary =
      failureText ?? (stale ? VerifyText.text("verify.trustedListsStale", "Stale") : nil)
    let indicator: VerifyDocumentRowValue.Indicator =
      trustedLists.isRefreshing ? .progress : failed ? .fails : stale ? .hidden : .holds
    return VerifyDocumentRowValue(
      text: VerifyText.text("verify.trustedListsFetched", "Fetched \(fetched)"),
      secondaryText: secondary,
      indicator: indicator
    )
  }

  /// Whether the lists need the user's attention.
  ///
  /// A fetch failed, and no lists are stored or the stored ones are
  /// stale. A failed refresh while current lists are stored changes
  /// nothing the user sees.
  internal static func needsAttention(failed: Bool, stored: Bool, stale: Bool) -> Bool {
    failed && (!stored || stale)
  }
}
