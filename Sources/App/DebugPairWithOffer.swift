// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG

  import CardCore
  import Foundation

  /// Pairs with an offer handed in on the command line.
  ///
  /// Pairing needs two devices and a camera, and a device driven from a
  /// cable has neither a holder nor a view of the other's screen. This
  /// stands in for the scan so the whole ceremony -- dial, handshake,
  /// confirmation, and the record both sides keep -- can be driven and
  /// measured without a hand on either device.
  ///
  /// It grants exactly what the scan grants and nothing more: the offer
  /// still has to be live, the peer still has to answer the handshake, and
  /// the pairing still ends in the same vault. The offer is never printed.
  ///
  /// DEBUG only.
  internal enum DebugPairWithOffer {
    // MARK: Static Properties

    /// How long a pairing is allowed to take.
    ///
    /// A dial across a network, a Noise handshake and two confirmations
    /// settle in under a second when they settle at all; the rest is the
    /// offer's own lifetime, which is what the requester waits out while
    /// the other device is being started.
    private static let attempts = 180
    private static let pause = Duration.seconds(1)

    /// The maximum length of a user-entered pairing code before it is treated as a full URI.
    private static let maxPairingCodeLength = 10

    /// What a script looks for on the line carrying the offer.
    internal static let offerPrefix = "offer-remote-reader: offer "

    // MARK: Static Functions

    /// Runs one pairing and reports whether a record came out of it.
    @MainActor
    internal static func run(offerURI: String) async -> DebugModeReport {
      let model = RappPairingModel()
      // A length, never the offer: it answers whether the whole of it
      // survived the cable, which is the one thing a caller cannot see.
      DebugConsole.emit("pair-with-offer: offer characters: " + String(offerURI.count))
      let trimmed = offerURI.trimmingCharacters(in: .whitespacesAndNewlines)
      let normalizedCode = RappPairingCode.normalize(trimmed)
      if trimmed.count <= maxPairingCodeLength, trimmed == normalizedCode {
        model.acceptPairingCode(normalizedCode)
      } else {
        // A full offer is not a substitute for the code it is keyed on.
        // The PAKE gives the two peers their shared secret, and that
        // secret is not carried in the offer, so pairing without the code
        // would be pairing without one.
        let code = DebugLaunchModes.offerCode()
        guard RappPairingCode.isValid(code) else {
          return DebugModeReport(
            lines: [
              "pair-with-offer: an offer needs the code it is keyed on",
              "pair-with-offer: set " + DebugLaunchModes.offerCodeVariable,
            ],
            succeeded: false)
        }
        model.acceptOfferWithoutScanning(trimmed, code: code)
      }

      for _ in 0..<attempts {
        switch model.phase {
        case .paired(let summary):
          return DebugModeReport(
            lines: [
              "pair-with-offer: paired over " + summary.transportProfile,
              "pair-with-offer: pairings held: " + String(heldPairCount()),
            ],
            succeeded: true)

        case .failed(let message):
          return DebugModeReport(
            lines: ["pair-with-offer: " + message],
            succeeded: false)

        case .connecting, .idle, .offer, .codeEntry:
          try? await Task.sleep(for: pause)
        }
      }
      return DebugModeReport(
        lines: ["pair-with-offer: the peer never completed the ceremony"],
        succeeded: false)
    }

    /// Makes an offer, prints it, and waits for a peer to take it.
    ///
    /// The requester's half of the same cable-driven ceremony. It prints
    /// the offer URI because that is the only way the other device can
    /// receive it with no camera and no screen between them; the offer is
    /// a bearer secret with a short life, and this exists in DEBUG builds
    /// alone.
    @MainActor
    internal static func offer() async -> DebugModeReport {
      let model = RappPairingModel()
      let initialCount = heldPairCount()
      model.createOffer()

      var announced = false
      for _ in 0..<attempts {
        if heldPairCount() > initialCount {
          return DebugModeReport(
            lines: [
              "offer-remote-reader: paired successfully",
              "offer-remote-reader: pairings held: " + String(heldPairCount()),
            ],
            succeeded: true)
        }
        switch model.phase {
        case .offer(let uri):
          if !announced {
            announced = true
            DebugConsole.emit(offerPrefix + uri)
          }
          try? await Task.sleep(for: pause)

        case .paired(let summary):
          return DebugModeReport(
            lines: [
              "offer-remote-reader: paired over " + summary.transportProfile,
              "offer-remote-reader: pairings held: " + String(heldPairCount()),
            ],
            succeeded: true)

        case .failed(let message):
          return DebugModeReport(
            lines: ["offer-remote-reader: " + message],
            succeeded: false)

        case .connecting, .idle, .codeEntry:
          try? await Task.sleep(for: pause)
        }
      }
      return DebugModeReport(
        lines: ["offer-remote-reader: no peer took the offer"],
        succeeded: false)
    }

    /// How many pairings this device holds after the attempt.
    ///
    /// A count, never an identifier: it answers whether the record landed.
    private static func heldPairCount() -> Int {
      ((try? RappDeviceVault().activePairIDs()) ?? []).count
    }
  }

#endif
