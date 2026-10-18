// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && REFINEID_LOCAL_CARD && os(iOS)
  import CryptoTokenKit

  /// The slot state, named for a trace line.
  extension TKSmartCardSlot.State {
    internal var traceName: String {
      switch self {
      case .missing:
        "missing"

      case .empty:
        "empty"

      case .probing:
        "probing"

      case .muteCard:
        "muteCard"

      case .validCard:
        "validCard"

      @unknown default:
        "state(\(rawValue))"
      }
    }
  }
#endif
