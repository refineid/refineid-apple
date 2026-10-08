// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG

  import CardCore
  import Foundation

  /// Drives both halves of a pairing from the command line.
  ///
  /// Pairing needs two devices and a person reading a code from one into
  /// the other, and a device driven from a cable has neither. The
  /// custodian half prints the code it shows; the requester half takes it
  /// as an argument, so the whole ceremony -- dial, CPace, handshake,
  /// grants, and the record both sides keep -- can be driven and measured
  /// without a hand on either device.
  ///
  /// It grants exactly what typing the code grants and nothing more: the
  /// offer still has to be live and both peers still have to prove the
  /// code. DEBUG only.
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

    /// What a script looks for on the line carrying the offer.
    internal static let offerPrefix = "offer-remote-reader: offer "

    // MARK: Static Functions

    /// Runs the requester half with a typed code and reports whether a
    /// record came out of it.
    @MainActor
    internal static func run(offerURI: String) async -> DebugModeReport {
      let model = RappPairingModel()
      let code = RappPairingCode.normalize(
        offerURI.trimmingCharacters(in: .whitespacesAndNewlines))
      guard RappPairingCode.isValid(code) else {
        return DebugModeReport(
          lines: ["pair-with-offer: the argument is not a pairing code"],
          succeeded: false)
      }
      model.acceptPairingCode(code)

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

    /// Shows a code, prints it, and waits for a requester to type it.
    ///
    /// The custodian's half of the same cable-driven ceremony. It prints
    /// the code because that is the only way the other device can receive
    /// it with no person between them; the code lives one minute, and this
    /// exists in DEBUG builds alone.
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
        case .offer(let code):
          if !announced {
            announced = true
            DebugConsole.emit(offerPrefix + code)
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
