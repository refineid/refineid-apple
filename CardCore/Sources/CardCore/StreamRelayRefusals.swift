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
      queue.asyncAfter(deadline: .now() + .milliseconds(Self.keptMilliseconds)) {
        [weak self] in
        self?.close(candidate)
      }
    }

    /// Closes every dialer still being refused.
    ///
    /// Called on the queue.
    internal func cancelAll() {
      for candidate in refused.values {
        candidate.cancel()
      }
      refused.removeAll()
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
    /// the dialer closes its side, or when it is kept no longer.
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

    private func close(_ candidate: NWConnection) {
      guard refused.removeValue(forKey: ObjectIdentifier(candidate)) != nil else { return }
      candidate.cancel()
    }
  }
#endif
