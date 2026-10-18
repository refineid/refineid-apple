// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import SwiftUI

  /// One paired phone: its name, its model when the record carries one,
  /// and whether it is on the network now.
  internal struct RemoteDeviceRow: View {
    private enum Layout {
      static let rowSpacing: CGFloat = 8
      static let textVerticalSpacing: CGFloat = 2
      static let statusBadgeSpacing: CGFloat = 4
      static let statusIndicatorSize: CGFloat = 6
      static let badgeTrailingPadding: CGFloat = 4
    }

    /// The name the phone introduced itself with.
    internal let name: String

    /// The hardware model identifier, when the record carries one.
    internal let modelName: String?

    internal let isOnline: Bool
    internal let isConnected: Bool
    internal let onDelete: () -> Void

    internal var body: some View {
      HStack(spacing: Layout.rowSpacing) {
        deviceInfo
        Spacer()
        statusBadge
          .padding(.trailing, Layout.badgeTrailingPadding)
        forgetButton
      }
      .contextMenu {
        Button(String(localized: "Forget"), role: .destructive) {
          onDelete()
        }
      }
    }

    private var deviceInfo: some View {
      VStack(alignment: .leading, spacing: Layout.textVerticalSpacing) {
        Text(name)
          .font(.body.weight(.medium))
        if let marketingModel {
          Text(marketingModel)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }

    /// The model by its marketing name, when the record carries one that
    /// the phone's name does not already say.
    private var marketingModel: String? {
      guard let modelName,
        let marketing = RappDeviceIdentity.friendlyMarketingName(from: modelName),
        marketing.caseInsensitiveCompare(name) != .orderedSame
      else { return nil }
      return marketing
    }

    private var forgetButton: some View {
      Button {
        onDelete()
      } label: {
        Image(systemName: "trash")
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityLabel(Text("Forget"))
      }
      .buttonStyle(.borderless)
      .help(String(localized: "Forget"))
    }

    @ViewBuilder private var statusBadge: some View {
      if isConnected || isOnline {
        HStack(spacing: Layout.statusBadgeSpacing) {
          Circle()
            .fill(Color.green)
            .frame(width: Layout.statusIndicatorSize, height: Layout.statusIndicatorSize)
          Text(isConnected ? String(localized: "Connected") : String(localized: "Online"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.green)
        }
      } else {
        Text("Offline")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

#endif
