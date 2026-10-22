// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Which transport the requester's next dial takes (RAPP transport
/// hierarchy §3).
///
/// The stream while Bonjour shows the phone; Bluetooth when it does not,
/// and also when a stream dial failed while Bonjour still showed it: a
/// suspended iPhone app leaves its record behind and answers no dial, so
/// trusting the record would never try Bluetooth (CC-72). A session already
/// open is kept whatever its transport.
internal struct RequesterTransportPolicy: Equatable, Sendable {
  /// Whether Bonjour shows the phone.
  internal var streamInSight = false
  /// Whether a stream dial failed since the phone last appeared on
  /// Bonjour.
  internal var streamFailedInSight = false
  /// Whether Bluetooth may be dialed: it was not found off or refused to
  /// this app since the pairing or the phone's presence last changed.
  internal var bluetoothUsable = true

  /// The transport of the next dial, or nil when neither can reach the
  /// phone.
  internal var nextDial: RequesterTransport? {
    if streamInSight, !streamFailedInSight { return .stream }
    if bluetoothUsable { return .bluetooth }
    return streamInSight ? .stream : nil
  }
}
