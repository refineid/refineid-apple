// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// When the trusted lists were fetched, whether they are stale or
/// could not be fetched, and the button that fetches them again.
internal struct VerifyTrustedListsSection: View {
  @ObservedObject internal var trustedLists: TrustedListStore

  internal var body: some View {
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
}
