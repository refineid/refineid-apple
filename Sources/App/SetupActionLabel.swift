// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import SwiftUI

  /// One sentence on accent: the label every setup action shares.
  internal struct SetupActionLabel: View {
    private enum Layout {
      static let buttonMinimumHeight: CGFloat = 64
      static let cornerRadius: CGFloat = 16
      static let horizontalPadding: CGFloat = 16
      static let verticalPadding: CGFloat = 12
    }

    internal let title: String
    internal let systemImage: String

    internal var body: some View {
      Label {
        Text(title)
          .multilineTextAlignment(.center)
      } icon: {
        Image(systemName: systemImage)
      }
      .font(.body.weight(.semibold))
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity)
      .frame(minHeight: Layout.buttonMinimumHeight)
      .padding(.horizontal, Layout.horizontalPadding)
      .padding(.vertical, Layout.verticalPadding)
      .background(Color.accentColor, in: RoundedRectangle(cornerRadius: Layout.cornerRadius))
      .contentShape(RoundedRectangle(cornerRadius: Layout.cornerRadius))
    }
  }
#endif
