// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import SwiftUI

  /// The paired phone's card while browser requests to it are paused.
  ///
  /// The token extension pauses after a request ends without a card or the
  /// holder's approval; resuming lets the next request reach the phone.
  internal struct RemoteCardPauseRow: View {
    private static let refresh: TimeInterval = 1

    @State private var resumedAt: Date?

    internal var body: some View {
      TimelineView(.periodic(from: .now, by: Self.refresh)) { context in
        if RemoteSignCoolDown.shared.pausedUntil(at: context.date) != nil,
          resumedAt.map({ context.date.timeIntervalSince($0) > Self.refresh }) ?? true
        {
          HStack {
            Text("Remote card paused")
              .foregroundStyle(.secondary)
            Button("Resume") {
              RemoteSignCoolDown.shared.resume()
              resumedAt = context.date
            }
          }
        }
      }
    }
  }

#endif
