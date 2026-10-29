// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(Network)
  import Network

  /// Accepts every connection a custodian's session listener gets and
  /// carries frames over each one apart (RAPP v26.10.29 §2.2.2): any number
  /// at once, one per client session, and an open connection is never a
  /// reason to refuse another.
  ///
  /// A connection that has not delivered one whole frame within the first
  /// frame timeout is closed, and at most ``maximumAwaitingFirstFrame``
  /// connections may wait for theirs at once. Neither bound touches a
  /// connection that presented its first frame; both bound what a dialer
  /// that never presents a preamble can hold.
  ///
  /// The transport carries opaque frames and never decodes protocol or card
  /// data; routing and authentication belong to the owner. All state is
  /// confined to one serial queue, and events reach the owner in the order
  /// the queue saw them.
  public final class StreamSessionListener: @unchecked Sendable {
    /// What the listener reports to its one owner.
    public enum Event: Sendable {
      /// The connection ended and delivers nothing more.
      case closed(StreamSessionConnection, StreamRelayTransportError)
      /// A dialer's connection is ready.
      case connected(StreamSessionConnection)
      /// The listener itself stopped; every connection closed before it.
      case ended(StreamRelayTransportError)
      /// One whole frame arrived on the connection.
      case frame(StreamSessionConnection, Data)
    }

    /// One accepted connection and the bytes it has sent.
    private struct Inbound {
      let connection: NWConnection
      var reader = StreamFrameReader()
      /// Whether the connection has delivered a whole frame.
      var framed = false
    }

    /// Seconds a connection may take to present its first whole frame.
    public static let firstFrameTimeoutSeconds = 5

    /// Connections that may wait for their first frame at once.
    public static let maximumAwaitingFirstFrame = 8

    private let onEvent: @Sendable (Event) -> Void
    private let firstFrameTimeout: DispatchTimeInterval
    private let queue = DispatchQueue(label: "fi.refineid.stream-session-listener")
    private var listener: NWListener?
    private var inbound: [StreamSessionConnection: Inbound] = [:]
    private var isFinished = false
    private var lastState = "not started"
    private var publishedName: String?

    /// What the listener last reported, for a caller diagnosing a dialer
    /// that cannot reach it.
    public var state: String {
      queue.sync { lastState }
    }

    /// The port this bound, once it is listening.
    public var port: UInt16? {
      queue.sync { listener?.port?.rawValue }
    }

    /// The instance name the service is registered under, once Bonjour has
    /// registered it; a conflict may have renamed it from the one asked for.
    public var registeredName: String? {
      queue.sync { publishedName }
    }

    /// Whether the listener accepts connections.
    public var isListening: Bool {
      queue.sync { listener != nil && !isFinished }
    }

    /// A listener reporting to one owner.
    @preconcurrency
    public convenience init(onEvent: @escaping @Sendable (Event) -> Void) {
      self.init(firstFrameTimeout: .seconds(Self.firstFrameTimeoutSeconds), onEvent: onEvent)
    }

    /// A listener that closes a connection silent for `firstFrameTimeout`.
    internal init(
      firstFrameTimeout: DispatchTimeInterval,
      onEvent: @escaping @Sendable (Event) -> Void
    ) {
      self.firstFrameTimeout = firstFrameTimeout
      self.onEvent = onEvent
    }

    /// Publishes the service under `displayName` with discovery attributes.
    public func start(displayName: String, txtRecord: [String: String]) {
      let record = StreamRelayListener.record(txtRecord)
      queue.async { self.publish(displayName: displayName, txtRecord: record) }
    }

    /// Replaces the published discovery attributes under the same name.
    public func updateTXTRecord(_ txtRecord: [String: String]) {
      let record = StreamRelayListener.record(txtRecord)
      queue.async {
        guard let listener = self.listener, let service = listener.service else { return }
        listener.service = NWListener.Service(
          name: service.name, type: StreamRelayListener.serviceType, domain: nil,
          txtRecord: record)
      }
    }

    /// Sends one frame on `connection`, or throws when it is not open.
    public func send(_ frame: Data, on connection: StreamSessionConnection) throws {
      guard let encoded = StreamRelayFraming.encode(frame) else {
        throw StreamRelayTransportError.invalidFrameLength
      }
      let open: NWConnection? = queue.sync { inbound[connection]?.connection }
      guard let open else { throw StreamRelayTransportError.notConnected }
      open.send(
        content: encoded,
        completion: .contentProcessed { _ in
          // A send that failed is reported by the connection's own state.
        })
    }

    /// Closes `connection` and reports it closed; the listener stays.
    public func disconnect(_ connection: StreamSessionConnection) {
      queue.async { self.close(connection, .disconnected) }
    }

    /// Stops listening, closing every connection.
    public func cancel() {
      queue.async { self.finish(.cancelled) }
    }

    private func publish(displayName: String, txtRecord: NWTXTRecord) {
      // Plain TCP: a listener that also offers a peer-to-peer link accepts
      // on that link and not on the network the dialer is using.
      let made: NWListener
      do {
        made = try NWListener(using: .tcp)
      } catch {
        finish(.unreachable)
        return
      }
      made.service = NWListener.Service(
        name: displayName, type: StreamRelayListener.serviceType, domain: nil,
        txtRecord: txtRecord)
      made.serviceRegistrationUpdateHandler = { [weak self] change in
        guard let self, case .add(let endpoint) = change,
          case .service(let name, _, _, _) = endpoint
        else { return }
        queue.async { self.publishedName = name }
      }
      made.newConnectionHandler = { [weak self] candidate in
        guard let self else {
          candidate.cancel()
          return
        }
        queue.async { self.accept(candidate) }
      }
      made.stateUpdateHandler = { [weak self] state in
        guard let self else { return }
        let description = String(describing: state)
        queue.async {
          self.lastState = description
          if case .failed = state { self.finish(.unreachable) }
        }
      }
      listener = made
      made.start(queue: queue)
    }

    private func accept(_ candidate: NWConnection) {
      let awaiting = inbound.values.filter { !$0.framed }.count
      guard !isFinished, awaiting < Self.maximumAwaitingFirstFrame else {
        candidate.cancel()
        return
      }
      let connection = StreamSessionConnection()
      inbound[connection] = Inbound(connection: candidate)
      candidate.stateUpdateHandler = { [weak self] state in
        guard let self else { return }
        switch state {
        case .ready:
          onEvent(.connected(connection))

        case .failed, .cancelled:
          queue.async { self.close(connection, .disconnected) }

        default:
          break
        }
      }
      candidate.start(queue: queue)
      queue.asyncAfter(deadline: .now() + firstFrameTimeout) { [weak self] in
        guard let self, inbound[connection]?.framed == false else { return }
        close(connection, .disconnected)
      }
      receiveNext(on: connection, from: candidate)
    }

    private func receiveNext(on connection: StreamSessionConnection, from open: NWConnection) {
      open.receive(
        minimumIncompleteLength: 1,
        maximumLength: StreamRelayFraming.maximumPayloadByteCount
      ) { [weak self] data, _, isComplete, error in
        guard let self else { return }
        queue.async {
          self.received(data, on: connection, from: open, ended: isComplete || error != nil)
        }
      }
    }

    private func received(
      _ data: Data?, on connection: StreamSessionConnection, from open: NWConnection, ended: Bool
    ) {
      guard var entry = inbound[connection], entry.connection === open else { return }
      if let data, !data.isEmpty {
        let frames: [Data]
        do {
          frames = try entry.reader.frames(after: data)
        } catch {
          close(connection, .malformedFrame)
          return
        }
        entry.framed = entry.framed || !frames.isEmpty
        inbound[connection] = entry
        for frame in frames {
          onEvent(.frame(connection, frame))
        }
      }
      guard !ended else {
        close(connection, .disconnected)
        return
      }
      receiveNext(on: connection, from: open)
    }

    private func close(_ connection: StreamSessionConnection, _ error: StreamRelayTransportError) {
      guard let entry = inbound.removeValue(forKey: connection) else { return }
      entry.connection.cancel()
      onEvent(.closed(connection, error))
    }

    private func finish(_ error: StreamRelayTransportError) {
      guard !isFinished else { return }
      isFinished = true
      for connection in Array(inbound.keys) {
        close(connection, .malformedFrame)
      }
      listener?.cancel()
      listener = nil
      onEvent(.ended(error))
    }
  }
#endif
