// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)
  import UIKit

  /// Where the app is, from UIKit's word for it.
  extension HolderAttention.AppState {
    /// The app state `state` names; a state this build does not know is
    /// taken for the background, where a summons is the safe answer.
    internal init(_ state: UIApplication.State) {
      switch state {
      case .active:
        self = .active

      case .inactive:
        self = .inactive

      case .background:
        self = .background

      @unknown default:
        self = .background
      }
    }
  }
#endif
