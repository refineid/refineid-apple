// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import RappEngine

@testable import CardCore

/// Hands the events one side of a stream channel reports to a ceremony, in
/// the order the channel reported them.
///
/// The requester has arrived once its pairing preamble is read; the
/// preamble is that arrival and never a ceremony message, so the ceremony
/// above is given the arrival and the frames after it.
internal final class StreamRelayFrameRelay: Sendable {
  /// What the ceremony is given.
  internal struct Receiver: Sendable {
    /// The requester's preamble arrived.
    internal let arrived: @Sendable () async -> Void
    /// One frame after the preamble.
    internal let frame: @Sendable (Data) async -> Void
  }

  /// The events one side of a stream channel carried, for a failure report.
  private actor SeenEvents {
    private var events: [String] = []

    var summary: String {
      events.joined(separator: ", ")
    }

    func record(_ event: StreamRelayEvent) {
      if case .frame(let payload) = event {
        events.append("frame(\(payload.count))")
      } else {
        events.append(String(describing: event))
      }
    }
  }

  private let events: AsyncStream<StreamRelayEvent>
  private let sink: AsyncStream<StreamRelayEvent>.Continuation
  private let seen = SeenEvents()

  /// What this side saw, for a caller reporting why a ceremony stalled.
  internal var summary: String {
    get async { await seen.summary }
  }

  internal init() {
    (events, sink) = AsyncStream.makeStream(of: StreamRelayEvent.self)
  }

  /// Takes one event on the reporting queue, keeping its place in line.
  internal func report(_ event: StreamRelayEvent) {
    sink.yield(event)
  }

  /// Delivers every reported event in order, until the channel ends.
  internal func serve(_ receiver: Receiver) async {
    var admission = StreamPairingAdmission(preamble: rappStreamPairingPreamble())
    for await event in events {
      await seen.record(event)
      switch admission.admit(event) {
      case .ignore, .reject:
        continue

      case .arrive:
        await receiver.arrived()

      case .forward:
        if case .frame(let payload) = event {
          await receiver.frame(payload)
        }
      }
    }
  }

  /// Ends delivery.
  internal func finish() {
    sink.finish()
  }
}
