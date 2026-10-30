// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import Network
  import RappEngine

  /// How the requester reaches the holder over the stream transport.
  extension RappPersistentRequesterClient {
    /// Starts the stream transport.
    ///
    /// The holder listens under a random name in
    /// session mode and this side dials the one whose rotating hints name
    /// its pairing. The dial opens with a session preamble whose routing
    /// is drawn fresh for that dial, so the holder learns which pairing
    /// arrived and an observer learns nothing it can follow. A vault
    /// holding no usable pairing settles the request at once instead of
    /// browsing for a peer that cannot exist.
    internal func startTransport() {
      Task { [weak self] in
        guard let self else { return }
        guard let pair = try? await resolvedPair() else {
          finish(error: .noActivePair)
          return
        }
        let found = StreamRelayBrowser(
          matchingRecord: { record in
            StreamRendezvousName.sessionRecord(record, holds: pair, at: Date())
          },
          onFound: { [weak self] endpoint in
            guard
              let preamble = try? pair.sessionPreamble(
                transportProfile: rappStreamProfileName())
            else {
              self?.finish(error: .noActivePair)
              return
            }
            self?.dialHolder(endpoint, preamble: preamble)
          })
        browser = found
        found.start()
      }
    }

    /// Hands one frame to the dialled holder.
    internal func sendOverTransport(_ frame: Data) async throws {
      guard let dialer else {
        throw RappRequesterClientError.transport
      }
      try await dialer.send(frame)
    }

    /// Stops browsing and dialling.
    internal func cancelTransport() {
      browser?.cancel()
      dialer?.cancel()
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
  }
#endif
