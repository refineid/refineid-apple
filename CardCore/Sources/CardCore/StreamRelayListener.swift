// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Darwin
import Foundation

#if canImport(Network)
  import Network

  /// Accepts one `fi.refineid.stream.v1` connection and carries frames over it.
  ///
  /// The card holder listens and the requester dials, which is the opposite
  /// of the nearby transport and is why this exists: peer discovery there
  /// depends on a mechanism two system generations no longer agree on, while
  /// a published service and a dialled port are carried by the plain name
  /// service both of them still speak.
  ///
  /// The transport carries opaque frames and never decodes protocol or card
  /// data; peer authentication belongs to the session above it.
  public final class StreamRelayListener: @unchecked Sendable {
    /// The Bonjour type this publishes and a dialer browses for.
    public static let serviceType = "_refineid-stream._tcp"

    private let onEvent: @Sendable (StreamRelayEvent) -> Void
    private let queue = DispatchQueue(label: "fi.refineid.stream-listener")
    private var listener: NWListener?
    private var connection: NWConnection?
    private var pending = Data()
    private var isFinished = false
    private var lastState = "not started"

    /// What the listener last reported, for a caller diagnosing a dialer
    /// that cannot reach it.
    public var state: String {
      queue.sync { lastState }
    }

    /// The port this bound, once it is listening.
    public var port: UInt16? {
      queue.sync { listener?.port?.rawValue }
    }

    /// Whether the listener is actively listening for incoming connections.
    public var isListening: Bool {
      queue.sync { listener != nil && !isFinished }
    }

    /// Listens under `displayName`, reporting to one owner.
    @preconcurrency
    public init(onEvent: @escaping @Sendable (StreamRelayEvent) -> Void) {
      self.onEvent = onEvent
    }

    /// Publishes the service and waits for one dialer.
    public func start(displayName: String) {
      queue.async { self.publish(displayName: displayName, txtRecord: nil) }
    }

    /// Publishes the service with discovery attributes and waits for one
    /// dialer.
    public func start(displayName: String, txtRecord: [String: String]) {
      var record = NWTXTRecord()
      for (key, value) in txtRecord {
        record[key] = value
      }
      queue.async { self.publish(displayName: displayName, txtRecord: record) }
    }

    /// Sends one frame to the dialer, or throws when none is connected.
    ///
    /// A frame handed over before a dialer arrived has nowhere to go. It is
    /// reported rather than dropped: a caller that sends too early otherwise
    /// waits for an answer to a message the peer never received.
    public func send(_ frame: Data) throws {
      guard let encoded = StreamRelayFraming.encode(frame) else {
        throw StreamRelayTransportError.invalidFrameLength
      }
      let open: NWConnection? = queue.sync { connection }
      guard let open else { throw StreamRelayTransportError.notConnected }
      open.send(
        content: encoded,
        completion: .contentProcessed { _ in
          // A send that failed is reported by the connection's own state.
        })
    }

    /// Disconnects the active connection and reports .closed, but keeps the
    /// listener active to accept subsequent connections on the same port.
    public func disconnect() {
      queue.async {
        self.handleConnectionClosure(.disconnected)
      }
    }

    /// Stops listening and reports the channel closed.
    public func cancel() {
      queue.async {
        self.finish(.cancelled)
      }
    }

    private func publish(displayName: String, txtRecord: NWTXTRecord?) {
      // Plain TCP: a listener that also offers a peer-to-peer link accepts
      // on that link and not on the network the dialer is using.
      let parameters = NWParameters.tcp
      let made: NWListener
      do {
        made = try NWListener(using: parameters)
      } catch {
        finish(.unreachable)
        return
      }
      if let txtRecord {
        made.service = NWListener.Service(
          name: displayName, type: Self.serviceType, domain: nil, txtRecord: txtRecord)
      } else {
        made.service = NWListener.Service(name: displayName, type: Self.serviceType)
      }
      made.newConnectionHandler = { [weak self] connection in
        self?.accept(connection)
      }
      made.stateUpdateHandler = { [weak self] state in
        guard let self else { return }
        let description = String(describing: state)
        queue.async { self.lastState = description }
        guard case .failed = state else { return }
        queue.async { self.finish(.unreachable) }
      }
      listener = made
      made.start(queue: queue)
    }

    private func accept(_ candidate: NWConnection) {
      queue.async { [weak self] in
        guard let self else { return }
        guard connection == nil, !isFinished else {
          candidate.cancel()
          return
        }
        connection = candidate
        pending = Data()
        candidate.stateUpdateHandler = { [weak self] state in
          guard let self else { return }
          switch state {
          case .ready:
            onEvent(.connected)

          case .failed, .cancelled:
            queue.async { [weak self] in
              self?.handleConnectionClosure(.disconnected)
            }

          default:
            break
          }
        }
        candidate.start(queue: queue)
        receiveNext(candidate)
      }
    }

    private func receiveNext(_ connection: NWConnection) {
      connection.receive(
        minimumIncompleteLength: 1,
        maximumLength: StreamRelayFraming.maximumPayloadByteCount
      ) { [weak self] data, _, isComplete, error in
        guard let self else { return }
        queue.async { [weak self] in
          guard let self else { return }
          guard self.connection === connection else { return }
          if let data, !data.isEmpty {
            pending.append(data)
            drainFrames()
          }
          if isComplete || error != nil {
            #if DEBUG
              print(
                "[StreamRelayListener] receiveNext ended isComplete=\(isComplete) "
                  + "error=\(String(describing: error))")
              fflush(stdout)
            #endif
            handleConnectionClosure(.disconnected)
            return
          }
          receiveNext(connection)
        }
      }
    }

    private func drainFrames() {
      while true {
        guard pending.count >= StreamRelayFraming.lengthPrefixByteCount else { return }
        let prefix = pending.prefix(StreamRelayFraming.lengthPrefixByteCount)
        guard let length = StreamRelayFraming.payloadByteCount(lengthPrefix: Data(prefix)) else {
          handleConnectionClosure(.malformedFrame)
          return
        }
        let total = StreamRelayFraming.lengthPrefixByteCount + length
        guard pending.count >= total else { return }
        let payload = pending.dropFirst(StreamRelayFraming.lengthPrefixByteCount).prefix(length)
        pending = Data(pending.dropFirst(total))
        onEvent(.frame(Data(payload)))
      }
    }

    private func handleConnectionClosure(_ error: StreamRelayTransportError) {
      #if DEBUG
        print("[StreamRelayListener] connection closed: \(error)")
        fflush(stdout)
      #endif
      guard let open = connection else { return }
      connection = nil
      pending = Data()
      open.cancel()
      onEvent(.closed(error))
    }

    private func finish(_ error: StreamRelayTransportError) {
      #if DEBUG
        print("[StreamRelayListener] finish: \(error)")
        fflush(stdout)
      #endif
      guard !isFinished else { return }
      isFinished = true
      let open = connection
      connection = nil
      open?.cancel()
      let activeListener = listener
      listener = nil
      activeListener?.cancel()
      pending = Data()
      onEvent(.closed(error))
    }
  }
#endif
