// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(Network)
  import Network

  /// A dialer that arrives while a connection is open: held until its
  /// first frame says whether it takes the connection's place.
  extension StreamRelayListener {
    /// Holds `candidate` until its first frame says whether it takes the
    /// open connection's place; a challenger that fails, stalls, or is
    /// refused goes without a word.
    internal func challenge(_ candidate: NWConnection) {
      challenger = candidate
      challengePending = Data()
      candidate.stateUpdateHandler = { [weak self] state in
        guard let self else { return }
        guard case .failed = state else { return }
        queue.async { [weak self] in self?.dismissChallenger(candidate) }
      }
      candidate.start(queue: queue)
      queue.asyncAfter(deadline: .now() + Self.challengeTimeout) { [weak self] in
        self?.dismissChallenger(candidate)
      }
      receiveChallenge(candidate)
    }

    internal func receiveChallenge(_ candidate: NWConnection) {
      candidate.receive(
        minimumIncompleteLength: 1,
        maximumLength: StreamRelayFraming.maximumPayloadByteCount
      ) { [weak self] data, _, isComplete, error in
        guard let self else { return }
        queue.async { [weak self] in
          guard let self, challenger === candidate else { return }
          if let data, !data.isEmpty {
            challengePending.append(data)
          }
          guard let first = firstChallengeFrame() else {
            if isComplete || error != nil {
              dismissChallenger(candidate)
            } else {
              receiveChallenge(candidate)
            }
            return
          }
          guard admitsReplacement?(first.frame) == true else {
            dismissChallenger(candidate)
            return
          }
          challenger = nil
          handleConnectionClosure(.disconnected)
          adopt(candidate, carrying: first.rest)
          onEvent(.connected)
          onEvent(.frame(first.frame))
          drainFrames()
          receiveNext(candidate)
        }
      }
    }

    /// The challenger's first frame and the bytes after it, once whole.
    internal func firstChallengeFrame() -> (frame: Data, rest: Data)? {
      guard challengePending.count >= StreamRelayFraming.lengthPrefixByteCount else { return nil }
      let prefix = Data(challengePending.prefix(StreamRelayFraming.lengthPrefixByteCount))
      guard let length = StreamRelayFraming.payloadByteCount(lengthPrefix: prefix) else {
        return (Data(), challengePending)
      }
      let total = StreamRelayFraming.lengthPrefixByteCount + length
      guard challengePending.count >= total else { return nil }
      let body = challengePending.dropFirst(StreamRelayFraming.lengthPrefixByteCount)
      return (Data(body.prefix(length)), Data(challengePending.dropFirst(total)))
    }

    internal func dismissChallenger(_ candidate: NWConnection) {
      guard challenger === candidate else { return }
      challenger = nil
      challengePending = Data()
      candidate.cancel()
    }
  }
#endif
