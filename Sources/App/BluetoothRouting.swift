// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD && REFINEID_STREAM_TRANSPORT
  import CardCore
  import RappEngine

  /// What the phone's GATT server queue routes and admits links with.
  internal struct BluetoothRouting {
    /// The pairings a link may route to.
    internal var records: [RappPairRecord] = []
    /// Refuses replayed routing on this server (RAPP v26.10.22 §2.2.1).
    internal var router = RappSessionRouter()
    /// The pairing each admitted link routed to, until the main actor
    /// takes it.
    internal var routed: [RappBleGattLink: RappPairRecord] = [:]
  }
#endif
