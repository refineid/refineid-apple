// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Darwin
import Foundation

#if canImport(Network)
  import Network

  /// Accepts one `fi.refineid.stream` connection and carries frames over it.
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
    private var reader = StreamFrameReader()
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

    /// Whether the listener is actively listening for incoming connections.
    public var isListening: Bool {
      queue.sync { listener != nil && !isFinished }
    }

    /// Listens under `displayName`, reporting to one owner; a dialer
    /// arriving while a connection is open is refused.
    @preconcurrency
    public init(onEvent: @escaping @Sendable (StreamRelayEvent) -> Void) {
      self.onEvent = onEvent
    }

    /// The published form of discovery attributes.
    internal static func record(_ attributes: [String: String]) -> NWTXTRecord {
      var record = NWTXTRecord()
      for (key, value) in attributes {
        record[key] = value
      }
      return record
    }

    /// Publishes the service and waits for one dialer.
    public func start(displayName: String) {
      queue.async { self.publish(displayName: displayName, txtRecord: nil) }
    }

    /// Publishes the service with discovery attributes and waits for one
    /// dialer.
    public func start(displayName: String, txtRecord: [String: String]) {
      let record = Self.record(txtRecord)
      queue.async { self.publish(displayName: displayName, txtRecord: record) }
    }

    /// Replaces the published discovery attributes under the same name,
    /// such as when rotating hints move to a new window.
    public func updateTXTRecord(_ txtRecord: [String: String]) {
      let record = Self.record(txtRecord)
      queue.async {
        guard let listener = self.listener, let service = listener.service else { return }
        listener.service = NWListener.Service(
          name: service.name, type: Self.serviceType, domain: nil, txtRecord: record)
      }
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
      made.serviceRegistrationUpdateHandler = { [weak self] change in
        guard let self, case .add(let endpoint) = change,
          case .service(let name, _, _, _) = endpoint
        else { return }
        queue.async { self.publishedName = name }
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
        guard !isFinished, connection == nil else {
          candidate.cancel()
          return
        }
        adopt(candidate)
        candidate.start(queue: queue)
        receiveNext(candidate)
      }
    }

    /// Makes `candidate` the connection and reports it connected once it
    /// is ready.
    private func adopt(_ candidate: NWConnection) {
      connection = candidate
      reader = StreamFrameReader()
      candidate.stateUpdateHandler = { [weak self] state in
        guard let self else { return }
        switch state {
        case .ready:
          onEvent(.connected)

        case .failed, .cancelled:
          queue.async { [weak self] in
            // A connection already closed reports nothing again.
            guard let self, connection === candidate else { return }
            handleConnectionClosure(.disconnected)
          }

        default:
          break
        }
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
            let frames: [Data]
            do {
              frames = try reader.frames(after: data)
            } catch {
              handleConnectionClosure(.malformedFrame)
              return
            }
            for frame in frames {
              onEvent(.frame(frame))
            }
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

    private func handleConnectionClosure(_ error: StreamRelayTransportError) {
      #if DEBUG
        print("[StreamRelayListener] connection closed: \(error)")
        fflush(stdout)
      #endif
      guard let open = connection else { return }
      connection = nil
      reader = StreamFrameReader()
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
      reader = StreamFrameReader()
      onEvent(.closed(error))
    }
  }
#endif
