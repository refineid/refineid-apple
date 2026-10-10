// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore
  import Foundation
  import RappEngine

  /// One active pair's rendezvous facts on the phone.
  ///
  /// The holder is the side whose listener the network lets everyone
  /// reach, so it publishes and the requester dials. It publishes under a
  /// random name in session mode, never under anything derived from the
  /// rendezvous token; the requester's opening frame is the session
  /// preamble built from that token -- the arrival that says which pairing
  /// the dial is for.
  internal struct PhoneStreamPairContext {
    /// This pair's local bookkeeping key; never published.
    internal let key: String

    /// The token the session preamble and the rotating hints derive from.
    internal let rendezvousToken: Data

    /// The opening frame a requester of this pair dials with.
    internal let sessionPreamble: Data

    /// The stream endpoints to dial, if this pair was established over explicit stream endpoints.
    internal let streamEndpoints: [String]

    /// The underlying pair record.
    internal let pairRecord: RappPairRecord

    /// Resolves the listening facts for all active pairs.
    internal static func resolveAll(vault: RappDeviceVault) -> [Self] {
      guard let activeIDs = try? vault.activePairIDs(), !activeIDs.isEmpty else { return [] }
      var results: [Self] = []
      for pairID in activeIDs {
        guard let pair = try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault) else {
          continue
        }
        let metadata = pair.metadata()
        guard
          let preamble = try? rappStreamSessionPreamble(
            rendezvousToken: metadata.rendezvousToken
          )
        else { continue }
        results.append(
          Self(
            key: pairID.map { String(format: "%02x", $0) }.joined(),
            rendezvousToken: metadata.rendezvousToken,
            sessionPreamble: preamble,
            streamEndpoints: metadata.streamEndpoints ?? [],
            pairRecord: pair
          )
        )
      }
      return results
    }
  }
#endif
