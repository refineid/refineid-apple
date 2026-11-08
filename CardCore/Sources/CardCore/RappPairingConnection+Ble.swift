// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine) && canImport(CoreBluetooth)
  import Foundation
  import os
  import RappEngine

  extension RappPairingConnection {
    /// What the link has reported so far.
    private struct BluetoothProgress {
      /// The bootstrap answer read before routing, handed on as the first
      /// frame once the preamble is routed.
      var bootstrap: Data?
      var isConnected = false
      var isFinished = false
    }

    /// How long a Bluetooth pairing connection has to connect, read the
    /// bootstrap answer and route its preamble before it counts as closed.
    public static let bluetoothDialMilliseconds: UInt64 = 10_000

    /// The wait an offer served again in place of `pairing-busy` asks for
    /// (RAPP v26.11.2 §4.2, "Busy Refusal" item 2).
    private static let offerServedAgainWaitMilliseconds: UInt64 = 0

    /// The wait the answer read again after a refused CPace step 1 asks for.
    ///
    /// A `pairing-busy` names its own, and the offer read before, served
    /// again, asks for none. Anything else is no busy answer, and the close
    /// that follows ends the connection.
    private static func busyWait(_ answer: Data, read bootstrap: Data?) -> UInt64? {
      if let wait = try? rappPairingBusyRetryAfterMs(answer) { return wait }
      return answer == bootstrap ? offerServedAgainWaitMilliseconds : nil
    }

    /// Hands one link event on as the connection reports it.
    private static func forward(
      _ event: RappBleGattEvent,
      progress: OSAllocatedUnfairLock<BluetoothProgress>,
      sink: AsyncStream<Event>.Continuation,
      onTrace: @Sendable (RappBleGattTrace) -> Void
    ) {
      switch event {
      case .bootstrap(let answer):
        progress.withLock { $0.bootstrap = answer }

      case .connected:
        let first = progress.withLock { state -> Data? in
          state.isConnected = true
          return state.bootstrap
        }
        sink.yield(.connected)
        if let first { sink.yield(.frame(first)) }

      case .frame(let frame):
        sink.yield(.frame(frame))

      case .attemptRefused(let answer):
        if let wait = busyWait(answer, read: progress.withLock { $0.bootstrap }) {
          sink.yield(.busy(retryAfterMilliseconds: wait))
        }

      case .closed:
        progress.withLock { $0.isFinished = true }
        sink.yield(.closed)
        sink.finish()

      case .trace(let step):
        onTrace(step)

      case .peer:
        break
      }
    }

    /// Opens a pairing connection to the RAPP peripheral `peer` and no
    /// other (RAPP v26.11.2 §5.2).
    ///
    /// The bootstrap answer read off the Bootstrap Characteristic is
    /// reported as the connection's first frame once routing finished, as
    /// a stream custodian serves it (§4.2, Bootstrap Read Flow). A CPace
    /// step 1 the custodian refused is reported as `busy`: the wait of the
    /// `pairing-busy` read again, or none when the offer was read again
    /// (§4.2, "Busy Refusal" item 2). A peripheral that serves no offer, or
    /// is not reached within ``bluetoothDialMilliseconds``, closes before
    /// `connected`. `onTrace` receives each link step.
    @preconcurrency
    public static func bluetooth(
      to peer: UUID,
      onTrace: @escaping @Sendable (RappBleGattTrace) -> Void
    ) -> Self {
      let (events, sink) = AsyncStream.makeStream(of: Event.self)
      let progress = OSAllocatedUnfairLock(initialState: BluetoothProgress())
      let link = RappBleGattCentral(purpose: .pairing, peers: .only(peer)) { event in
        forward(event, progress: progress, sink: sink, onTrace: onTrace)
      }
      link.start()
      let bound = Task {
        try? await Task.sleep(for: .milliseconds(bluetoothDialMilliseconds))
        guard !Task.isCancelled else { return }
        let stalled = progress.withLock { !$0.isConnected && !$0.isFinished }
        if stalled { link.cancel() }
      }
      return Self(
        transport: RappClosureFrameTransport(
          sender: { frame in try await link.send(frame) },
          closer: {
            bound.cancel()
            link.cancel()
          }),
        transportProfile: RappBleGattProfile.name,
        events: events)
    }
  }
#endif
