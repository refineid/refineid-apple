// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation

  /// One pairing connection a requester opened to an endpoint found in
  /// pairing mode.
  ///
  /// The connection sends its pairing preamble when it opens and bounds its
  /// own dialling: one that cannot be opened reports `closed`.
  public struct RappPairingConnection: Sendable {
    // MARK: Nested Types

    /// What the connection reports, in order.
    public enum Event: Sendable, Equatable {
      /// The connection closed, or could not be opened.
      case closed
      /// The connection is open and its pairing preamble sent.
      case connected
      /// One complete frame from the custodian; the first is its offer.
      case frame(Data)
    }

    // MARK: Static Properties

    /// How long an open connection has to serve the custodian's offer,
    /// which a custodian sends as its first frame (RAPP v26.10.22 §4.2,
    /// Bootstrap Read Flow item 2).
    public static let offerReadMilliseconds: UInt64 = 5_000

    // MARK: Properties

    /// Carries the ceremony's frames to the custodian and closes the
    /// connection.
    public let transport: any RappFrameTransport
    /// The connection's events, ending with `closed`.
    public let events: AsyncStream<Event>

    // MARK: Lifecycle

    /// A connection the platform opened, reporting on `events`.
    public init(transport: any RappFrameTransport, events: AsyncStream<Event>) {
      self.transport = transport
      self.events = events
    }
  }
#endif
