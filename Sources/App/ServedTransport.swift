// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore

  /// The transport one session the phone serves runs over.
  internal enum ServedTransport: Hashable {
    #if REFINEID_STREAM_TRANSPORT
      /// One central's Bluetooth link.
      case bluetooth(RappBleGattLink)
      /// One connection on the session listener.
      case stream(StreamSessionConnection)
    #else
      /// The nearby connection.
      case nearby
    #endif
  }
#endif
