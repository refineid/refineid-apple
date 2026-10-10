// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The paired phone's card while browser requests to it are paused.
  ///
  /// The token extension pauses after a request ends without a card or the
  /// holder's approval; resuming lets the next request reach the phone.
  internal struct RemoteCardPauseRow: View {
    private let pause = RemoteCardPause.shared

    internal var body: some View {
      if pause.pausedUntil != nil {
        HStack {
          Text("Remote card paused")
            .foregroundStyle(.secondary)
          Button("Resume") {
            pause.resume()
          }
        }
      }
    }
  }

#endif
