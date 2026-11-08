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
  /// with none to send, it drops as it opens. A link made with an open
  /// failure never opens.
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
    /// The transport profile of the link.
    nonisolated internal let transportProfile: String
    private let servedOffer: Data?
    private let dropAfter: Int?
    /// The wait a custodian answers the requester's first frame with, in
    /// place of taking it; nil for a link that carries it.
    private var busyAtStepOne: UInt64?
    private let openFailure: RappPairingConnection.OpenFailure?
    private var custodian: RappPairingCoordinator?
    private var isDown = false

    // MARK: Lifecycle

    /// A stream link to a custodian ceremony attached later, or to
    /// nothing but `servedOffer`.
    internal init(servedOffer: Data?, dropAfter: Int?) {
      self.init(
        servedOffer: servedOffer, dropAfter: dropAfter,
        transportProfile: RappIntegrationFixtures.transportProfile)
    }

    /// A link of `transportProfile` to a custodian ceremony attached
    /// later, or to nothing but `servedOffer`.
    internal init(servedOffer: Data?, dropAfter: Int?, transportProfile: String) {
      self.transportProfile = transportProfile
      self.servedOffer = servedOffer
      self.dropAfter = dropAfter
      openFailure = nil
      (events, sink) = AsyncStream.makeStream(of: RappPairingConnection.Event.self)
    }

    /// A link to a custodian that dialling cannot reach, for `failure`.
    internal init(failingToOpen failure: RappPairingConnection.OpenFailure) {
      transportProfile = RappIntegrationFixtures.transportProfile
      servedOffer = nil
      dropAfter = nil
      openFailure = failure
      (events, sink) = AsyncStream.makeStream(of: RappPairingConnection.Event.self)
    }

    // MARK: Functions

    /// Answers the requester's CPace step 1 busy with `wait`, as a BLE
    /// custodian that cannot admit the attempt does.
    internal func answerStepOneBusy(wait: UInt64) {
      busyAtStepOne = wait
    }

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
        transportProfile: transportProfile,
        events: events)
    }

    internal func attach(_ custodian: RappPairingCoordinator) {
      self.custodian = custodian
    }

    private func open() async {
      isOpened = true
      if let openFailure {
        isDown = true
        sink.yield(.notOpened(openFailure))
        sink.finish()
        return
      }
      guard dropAfter != 0 else {
        await linkDown()
        return
      }
      sink.yield(.connected)
      if let servedOffer {
        sink.yield(.frame(servedOffer))
      } else if transportProfile == RappBleGattProfile.name,
        let answer = try? custodian?.bootstrapAnswer()
      {
        // A BLE requester reads the offer off the Bootstrap Characteristic.
        sink.yield(.frame(answer))
      }
      guard let custodian else { return }
      if await custodian.attach(custodianTransport(), transportProfile: transportProfile) {
        await custodian.transportConnected()
      }
    }

    private func requesterSends(_ frame: Data) async {
      requesterSent.frames.append(frame)
      guard !isDown else { return }
      if let busyAtStepOne {
        // A BLE custodian refuses the step 1 write and the requester reads
        // the bootstrap characteristic again (§4.2, "Busy Refusal" item 2).
        sink.yield(.busy(retryAfterMilliseconds: busyAtStepOne))
        await linkDown()
        return
      }
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
