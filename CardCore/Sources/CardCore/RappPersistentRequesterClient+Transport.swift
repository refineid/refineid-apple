// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(MultipeerConnectivity) && canImport(RappEngine)
  import Foundation
  import Network
  import RappEngine

  /// How the requester reaches the holder, whichever transport this build
  /// carries.
  extension RappPersistentRequesterClient {
    /// Starts whichever transport this build carries.
    ///
    /// Over the stream transport the holder listens under a random name in
    /// session mode and this side dials the one whose rotating hints name
    /// its pairing; the dial's opening frame is the pairing's session
    /// preamble, so the holder knows which pairing arrived. Nothing derived
    /// from the rendezvous token is browsed for by name. A vault holding no usable pairing settles the request at
    /// once instead of browsing for a peer that cannot exist.
    internal func startTransport() {
      #if REFINEID_STREAM_TRANSPORT
        Task { [weak self] in
          guard let self else { return }
          guard let facts = await rendezvousFacts() else {
            finish(error: .noActivePair)
            return
          }
          let token = facts.rendezvousToken
          let found = StreamRelayBrowser(
            matchingRecord: { record in
              StreamRendezvousName.sessionRecord(record, mayHold: token, at: Date())
            },
            onFound: { [weak self] endpoint in
              self?.dialHolder(endpoint, preamble: facts.preamble)
            })
          browser = found
          found.start()
        }
      #else
        relay.start()
      #endif
    }

    /// Hands one frame to whichever transport this build carries.
    internal func sendOverTransport(_ frame: Data) async throws {
      #if REFINEID_STREAM_TRANSPORT
        guard let dialer else {
          throw RappRequesterClientError.transport
        }
        try await dialer.send(frame)
      #else
        try relay.send(frame)
      #endif
    }

    /// Stops whichever transport this build carries.
    internal func cancelTransport() {
      #if REFINEID_STREAM_TRANSPORT
        browser?.cancel()
        dialer?.cancel()
      #else
        relay.cancel()
      #endif
    }

    #if REFINEID_STREAM_TRANSPORT
      /// The token the holder's hints are checked against and the frame to
      /// open with, both from the pairing this request will run over.
      private func rendezvousFacts() async -> (rendezvousToken: Data, preamble: Data)? {
        guard let pair = try? await resolvedPair() else { return nil }
        let metadata = pair.metadata()
        guard
          let preamble = try? rappStreamSessionPreamble(
            rendezvousToken: metadata.rendezvousToken
          )
        else { return nil }
        return (metadata.rendezvousToken, preamble)
      }

      /// Dials the holder found in session mode.
      private func dialHolder(_ endpoint: NWEndpoint, preamble: Data) {
        let made = StreamRelaySession(
          service: endpoint,
          preamble: preamble
        ) { [weak self] event in
          self?.receive(PersistentRelayEvent(event))
        }
        guard dialer == nil else { return }
        dialer = made
        made.start()
      }
    #endif
  }
#endif
