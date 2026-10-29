// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(Network)
  import Network

  /// Answers the dialers that reach a ``StreamRelayListener`` while it
  /// carries a connection, and closes them.
  ///
  /// Each refused dialer's first frame is handed to the listener owner's
  /// answer, which a pairing custodian makes its `pairing-busy` (RAPP
  /// v26.10.29 §4.2, "Busy Refusal"); the connection being carried sees
  /// none of it. All state is confined to the listener's queue.
  internal final class StreamRelayRefusals: @unchecked Sendable {
    /// How long a refused dialer is kept from its accept, in milliseconds:
    /// time to send its first frame and read the answer.
    internal static let keptMilliseconds = 2_000

    private let queue: DispatchQueue
    private let answer: StreamRelayListener.BusyAnswer
    /// Dialers refused and not yet closed.
    private var refused: [ObjectIdentifier: NWConnection] = [:]
    /// Each refused dialer's bound: from accept until its answer is sent,
    /// then the end-of-stream wait.
    private var bounds: [ObjectIdentifier: DispatchWorkItem] = [:]

    /// Refusals on `queue`, answering each dialer with `answer`.
    internal init(queue: DispatchQueue, answer: @escaping StreamRelayListener.BusyAnswer) {
      self.queue = queue
      self.answer = answer
    }

    /// Reads the first frame of `candidate`, answers it, and closes it.
    ///
    /// Called on the queue.
    internal func refuse(_ candidate: NWConnection) {
      refused[ObjectIdentifier(candidate)] = candidate
      candidate.start(queue: queue)
      readFirstFrame(of: candidate, reader: StreamFrameReader())
      bound(candidate, milliseconds: Self.keptMilliseconds)
    }

    /// Closes every dialer still being refused.
    ///
    /// Called on the queue.
    internal func cancelAll() {
      for candidate in refused.values {
        candidate.cancel()
      }
      refused.removeAll()
      for pending in bounds.values {
        pending.cancel()
      }
      bounds.removeAll()
    }

    private func readFirstFrame(of candidate: NWConnection, reader: StreamFrameReader) {
      candidate.receive(
        minimumIncompleteLength: 1,
        maximumLength: StreamRelayFraming.maximumPayloadByteCount
      ) { [weak self] data, _, isComplete, error in
        guard let self else { return }
        queue.async {
          self.received(data, of: candidate, reader: reader, ended: isComplete || error != nil)
        }
      }
    }

    private func received(
      _ data: Data?, of candidate: NWConnection, reader: StreamFrameReader, ended: Bool
    ) {
      guard refused[ObjectIdentifier(candidate)] != nil else { return }
      var next = reader
      let first: Data?
      do {
        first = try next.frames(after: data ?? Data()).first
      } catch {
        close(candidate)
        return
      }
      if let first {
        send(answer(first), andClose: candidate)
        return
      }
      guard !ended else {
        close(candidate)
        return
      }
      readFirstFrame(of: candidate, reader: next)
    }

    /// Sends `reply` as the refused dialer's last frame, then closes it once
    /// the dialer closes its side, or after the listener's end-of-stream
    /// wait, which replaces the bound from accept.
    private func send(_ reply: Data?, andClose candidate: NWConnection) {
      guard let reply, let encoded = StreamRelayFraming.encode(reply) else {
        close(candidate)
        return
      }
      candidate.send(
        content: encoded, contentContext: .finalMessage, isComplete: true,
        completion: .contentProcessed { _ in
          // The dialer's end of stream, or the bound, closes it.
        })
      bound(candidate, milliseconds: StreamRelayListener.endingWaitMilliseconds)
      awaitEnd(of: candidate)
    }

    /// Discards what the dialer still sends until it closes its side.
    private func awaitEnd(of candidate: NWConnection) {
      candidate.receive(
        minimumIncompleteLength: 1,
        maximumLength: StreamRelayFraming.maximumPayloadByteCount
      ) { [weak self] _, _, isComplete, error in
        guard let self else { return }
        queue.async {
          if isComplete || error != nil {
            self.close(candidate)
          } else if self.refused[ObjectIdentifier(candidate)] != nil {
            self.awaitEnd(of: candidate)
          }
        }
      }
    }

    /// Closes `candidate` after `milliseconds`, replacing its earlier bound.
    private func bound(_ candidate: NWConnection, milliseconds: Int) {
      let key = ObjectIdentifier(candidate)
      bounds[key]?.cancel()
      let expiry = DispatchWorkItem { [weak self] in self?.close(candidate) }
      bounds[key] = expiry
      queue.asyncAfter(deadline: .now() + .milliseconds(milliseconds), execute: expiry)
    }

    private func close(_ candidate: NWConnection) {
      let key = ObjectIdentifier(candidate)
      bounds.removeValue(forKey: key)?.cancel()
      guard refused.removeValue(forKey: key) != nil else { return }
      candidate.cancel()
    }
  }
#endif
