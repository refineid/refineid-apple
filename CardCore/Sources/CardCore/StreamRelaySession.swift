// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(Network)
  import Network

  /// A single TCP dialer for the `fi.refineid.stream` transport profile.
  ///
  /// The proxy dials the requester's listener endpoints in order and, on the
  /// first ready connection, releases the caller-provided plaintext preamble
  /// frame before anything else. The transport carries opaque RAPP frames and
  /// never decodes protocol or card-operation data; peer authentication
  /// belongs to RAPP rather than the underlay.
  ///
  /// All state is confined to one serial queue. Each dial attempt carries a
  /// generation, and callbacks from superseded attempts are dropped.
  public final class StreamRelaySession: @unchecked Sendable {
    /// How long one endpoint is given before the next is tried.
    private static let attemptSeconds = 3.0

    /// How many times a published service is dialled before giving up.
    ///
    /// A name can resolve to more than one address, and one of them can be
    /// a record its listener no longer answers on: a peer that was killed
    /// leaves its registration behind until it ages out. Dialling the name
    /// again resolves it afresh, which is how the live address is reached
    /// while the dead one is still being advertised.
    private static let serviceAttempts = 5

    /// How long to pause between failed service dials so the listener has time to settle.
    private static let serviceRedialDelaySeconds: TimeInterval = 0.25

    private let endpoints: [StreamRelayEndpoint]
    private let preamble: Data
    private let onEvent: @Sendable (StreamRelayEvent) -> Void
    private let queue = DispatchQueue(label: "fi.refineid.stream-relay")
    private var connection: NWConnection?
    private var isStarted = false
    private var nextEndpointIndex = 0
    private var generation = 0
    private var isReady = false
    private var isFinished = false
    private var service: NWEndpoint?

    /// Builds a dialer over the listener's address literals.
    ///
    /// Events go to one owner. Unparseable literals are dropped; the
    /// preamble frame is released first on the connection that becomes
    /// ready.
    @preconcurrency
    public init(
      endpointLiterals: [String],
      preamble: Data,
      onEvent: @escaping @Sendable (StreamRelayEvent) -> Void
    ) {
      self.endpoints = endpointLiterals.compactMap(StreamRelayEndpoint.init)
      self.preamble = preamble
      self.onEvent = onEvent
    }

    /// Builds a dialer for one already-found service endpoint.
    ///
    /// A published service resolves itself when dialled, so a caller that
    /// found one has no address literal to pass and needs none.
    @preconcurrency
    public convenience init(
      service: NWEndpoint,
      preamble: Data,
      onEvent: @escaping @Sendable (StreamRelayEvent) -> Void
    ) {
      self.init(endpointLiterals: [], preamble: preamble, onEvent: onEvent)
      self.service = service
    }

    /// Dials the first endpoint; later endpoints are tried in order until
    /// one connects.
    ///
    /// Repeat calls are ignored: each one would otherwise consume the next
    /// endpoint and strand the dial already in flight.
    public func start() {
      queue.async {
        guard !self.isStarted, !self.isFinished else { return }
        self.isStarted = true
        self.dialNext()
      }
    }

    /// Sends one opaque frame to the connected listener, returning after the
    /// frame was released to the transport.
    public func send(_ frame: Data) async throws {
      guard let framed = StreamRelayFraming.encode(frame) else {
        throw StreamRelayTransportError.invalidFrameLength
      }
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        queue.async {
          guard !self.isFinished, self.isReady, let connection = self.connection
          else {
            continuation.resume(
              throwing: StreamRelayTransportError.notConnected
            )
            return
          }
          connection.send(
            content: framed,
            completion: .contentProcessed { error in
              if let error {
                continuation.resume(
                  throwing: StreamRelayTransportError.send(
                    String(describing: error)
                  )
                )
              } else {
                continuation.resume()
              }
            }
          )
        }
      }
    }

    /// Disconnects and reports the channel closed.
    public func cancel() {
      queue.async { self.finish(.cancelled) }
    }

    private func dialNext() {
      guard !isFinished else { return }
      let dialed: NWConnection
      if let service {
        guard nextEndpointIndex < Self.serviceAttempts else {
          finish(.unreachable)
          return
        }
        nextEndpointIndex += 1
        dialed = NWConnection(to: service, using: .tcp)
      } else {
        guard nextEndpointIndex < endpoints.count else {
          finish(.unreachable)
          return
        }
        let endpoint = endpoints[nextEndpointIndex]
        nextEndpointIndex += 1
        dialed = NWConnection(
          host: NWEndpoint.Host(endpoint.host),
          port: NWEndpoint.Port(rawValue: endpoint.port) ?? .any,
          using: .tcp
        )
      }
      generation += 1
      let attempt = generation
      isReady = false

      connection = dialed
      dialed.stateUpdateHandler = { [weak self] state in
        self?.handleState(state, attempt: attempt, connection: dialed)
      }
      dialed.start(queue: queue)
      waitOut(attempt: attempt, connection: dialed)
    }

    /// Gives one dial its time before the next is tried.
    ///
    /// Every dial is bounded, not only one that reports itself waiting: a
    /// connection to an address nothing answers on stays preparing, and a
    /// preparing dial that is never given up on is a peer that never
    /// arrives.
    private func waitOut(attempt: Int, connection: NWConnection) {
      queue.asyncAfter(deadline: .now() + Self.attemptSeconds) { [weak self] in
        guard let self, attempt == generation, !isFinished, !isReady else { return }
        connection.cancel()
        dialNext()
      }
    }

    private func handleState(
      _ state: NWConnection.State,
      attempt: Int,
      connection: NWConnection
    ) {
      guard attempt == generation, !isFinished else { return }
      switch state {
      case .ready:
        guard let framedPreamble = StreamRelayFraming.encode(preamble) else {
          finish(.malformedFrame)
          return
        }
        isReady = true
        connection.send(
          content: framedPreamble,
          completion: .contentProcessed { [weak self] error in
            guard let self, error != nil else { return }
            queue.async { self.finish(.disconnected) }
          }
        )
        onEvent(.connected)
        receiveLengthPrefix(attempt: attempt, connection: connection)

      case .waiting:
        // The dial's own deadline decides when to move on.
        break

      case .failed:
        handleDialFailed(isReady: isReady, connection: connection)

      case .cancelled:
        finish(.cancelled)

      case .setup, .preparing:
        break

      @unknown default:
        break
      }
    }

    private func handleDialFailed(isReady: Bool, connection: NWConnection) {
      if isReady {
        finish(.disconnected)
      } else {
        generation += 1
        connection.cancel()
        let delay = service != nil ? Self.serviceRedialDelaySeconds : 0
        if delay > 0 {
          queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.dialNext()
          }
        } else {
          dialNext()
        }
      }
    }

    private func receiveLengthPrefix(attempt: Int, connection: NWConnection) {
      connection.receive(
        minimumIncompleteLength: StreamRelayFraming.lengthPrefixByteCount,
        maximumLength: StreamRelayFraming.lengthPrefixByteCount
      ) { [weak self] data, _, _, error in
        guard let self, attempt == generation, !isFinished else { return }
        guard error == nil,
          let data, data.count == StreamRelayFraming.lengthPrefixByteCount
        else {
          finish(.disconnected)
          return
        }
        guard
          let payloadByteCount = StreamRelayFraming.payloadByteCount(
            lengthPrefix: data
          )
        else {
          finish(.malformedFrame)
          return
        }
        receivePayload(
          byteCount: payloadByteCount,
          attempt: attempt,
          connection: connection
        )
      }
    }

    private func receivePayload(
      byteCount: Int,
      attempt: Int,
      connection: NWConnection
    ) {
      connection.receive(
        minimumIncompleteLength: byteCount,
        maximumLength: byteCount
      ) { [weak self] data, _, _, error in
        guard let self, attempt == generation, !isFinished else { return }
        guard error == nil, let data, data.count == byteCount else {
          finish(.disconnected)
          return
        }
        onEvent(.frame(data))
        receiveLengthPrefix(attempt: attempt, connection: connection)
      }
    }

    private func finish(_ error: StreamRelayTransportError) {
      guard !isFinished else { return }
      isFinished = true
      generation += 1
      connection?.cancel()
      connection = nil
      onEvent(.closed(error))
    }
  }
#endif
