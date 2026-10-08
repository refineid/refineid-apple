// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

@main
internal struct NFCCardTimingApp: App {
  internal var body: some Scene {
    WindowGroup {
      NavigationStack {
        CardTimingView()
      }
    }
  }
}
