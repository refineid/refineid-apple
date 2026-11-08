// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  extension RappPairingCoordinator {
    /// One pairing connection and the offer entry it binds (RAPP v26.11.2
    /// §4.2, Bootstrap Read Flow item 4).
    internal struct Binding: Sendable {
      // MARK: Properties

      internal let transport: any RappFrameTransport
      /// The registered transport profile of the connection (§2.2).
      internal let transportProfile: String
      /// The profile's registered candidate identifier (§2.2).
      internal let candidateID: String

      // MARK: Lifecycle

      /// The binding of `transport`, a connection of `transportProfile`.
      ///
      /// - Throws: ``RappBindingError/InvalidInput`` for an unregistered
      ///   transport profile.
      internal init(transport: any RappFrameTransport, transportProfile: String) throws {
        guard let identifier = rappCandidateIdentifier(transportProfile: transportProfile) else {
          throw RappBindingError.InvalidInput
        }
        self.transport = transport
        self.transportProfile = transportProfile
        candidateID = identifier
      }
    }

    /// Carries nothing: a custodian's ceremony before any connection is
    /// attached.
    private static let unattached = RappClosureFrameTransport(
      sender: { _ in throw RappBindingError.WrongPhase },
      closer: {
        // No connection to close.
      })

    /// The connection the ceremony runs on now.
    internal var transport: any RappFrameTransport {
      binding?.transport ?? Self.unattached
    }

    /// The candidate identifier of the connection the ceremony runs on;
    /// empty, which no offer entry names, before one is attached.
    internal var candidateID: String {
      binding?.candidateID ?? ""
    }

    /// Hands the custodian's ceremony the pairing connection that arrived on
    /// `transport`, a connection of `transportProfile`; ``transportConnected()``
    /// follows.
    ///
    /// Only an idle offer takes a connection, of a transport its offer
    /// lists; false otherwise, and the caller answers the connection busy
    /// with ``busyAnswer()`` (RAPP v26.11.2 §4.2, "Busy Refusal").
    @discardableResult
    public func attach(_ transport: any RappFrameTransport, transportProfile: String) -> Bool {
      guard role == .proxy, state == .offer,
        offeredTransportProfiles.contains(transportProfile),
        let attached = try? Binding(transport: transport, transportProfile: transportProfile)
      else { return false }
      binding = attached
      return true
    }
  }
#endif
