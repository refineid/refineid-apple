// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD && REFINEID_STREAM_TRANSPORT
  import CardCore

  /// The transport the phone's open session runs over.
  internal enum ServedTransport: Equatable {
    case bluetooth(RappBleGattLink)
    case stream
  }
#endif
