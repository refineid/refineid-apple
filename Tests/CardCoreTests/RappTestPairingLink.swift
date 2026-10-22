// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine

  /// One in-memory pairing connection between a requester's search and a
  /// custodian, recording what each side sent.
  ///
  /// The custodian is a real ceremony, or nothing but an offer served as
  /// the first frame. The link drops, as a network does, when the
  /// requester closes it or after the custodian sent `dropAfter` frames;
  /// with none to send, it drops as it opens.
  internal actor RappTestPairingLink {
    // MARK: Properties

    /// What the requester's side of the connection reports.
    nonisolated internal let events: AsyncStream<RappPairingConnection.Event>
    /// The requester's frames, and how many times it closed the link.
    internal private(set) var requesterSent: (frames: [Data], closeCount: Int) = ([], 0)
    /// The custodian's frames, and how many times it closed the link.
    internal private(set) var custodianSent: (frames: [Data], closeCount: Int) = ([], 0)
    /// Whether the requester opened this link.
    internal private(set) var isOpened = false

    private let sink: AsyncStream<RappPairingConnection.Event>.Continuation
    private let servedOffer: Data?
    private let dropAfter: Int?
    private var custodian: RappPairingCoordinator?
    private var isDown = false

    // MARK: Lifecycle

    /// A link to a custodian ceremony attached later, or to nothing but
    /// `servedOffer`.
    internal init(servedOffer: Data?, dropAfter: Int?) {
      self.servedOffer = servedOffer
      self.dropAfter = dropAfter
      (events, sink) = AsyncStream.makeStream(of: RappPairingConnection.Event.self)
    }

    // MARK: Functions

    /// The custodian's end of the link, its ceremony's transport.
    nonisolated internal func custodianTransport() -> RappClosureFrameTransport {
      RappClosureFrameTransport(
        sender: { frame in await self.custodianSends(frame) },
        closer: { await self.custodianCloses() })
    }

    /// The requester's end of the link, as dialling it gives it.
    nonisolated internal func dial() -> RappPairingConnection {
      Task { await open() }
      return RappPairingConnection(
        transport: RappClosureFrameTransport(
          sender: { frame in await self.requesterSends(frame) },
          closer: { await self.requesterCloses() }),
        events: events)
    }

    internal func attach(_ custodian: RappPairingCoordinator) {
      self.custodian = custodian
    }

    private func open() async {
      isOpened = true
      guard dropAfter != 0 else {
        await linkDown()
        return
      }
      sink.yield(.connected)
      if let servedOffer {
        sink.yield(.frame(servedOffer))
      }
      await custodian?.transportConnected()
    }

    private func requesterSends(_ frame: Data) async {
      requesterSent.frames.append(frame)
      guard !isDown else { return }
      await custodian?.receive(frame)
    }

    private func requesterCloses() async {
      requesterSent.closeCount += 1
      await linkDown()
    }

    private func custodianSends(_ frame: Data) async {
      custodianSent.frames.append(frame)
      guard !isDown else { return }
      sink.yield(.frame(frame))
      if let dropAfter, custodianSent.frames.count >= dropAfter {
        await linkDown()
      }
    }

    private func custodianCloses() async {
      custodianSent.closeCount += 1
      await linkDown()
    }

    /// Both ends see the link go down once.
    private func linkDown() async {
      guard !isDown else { return }
      isDown = true
      sink.yield(.closed)
      sink.finish()
      await custodian?.transportClosed()
    }
  }
#endif
