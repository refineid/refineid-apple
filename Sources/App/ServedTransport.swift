// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore

  /// The transport one session the phone serves runs over.
  internal enum ServedTransport: Hashable {
    /// One central's Bluetooth link.
    case bluetooth(RappBleGattLink)
    /// One connection on the session listener.
    case stream(StreamSessionConnection)
  }
#endif
