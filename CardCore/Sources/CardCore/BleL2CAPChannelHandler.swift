// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(CoreBluetooth) && !os(macOS)
  import CoreBluetooth

  /// Wraps a `CBL2CAPChannel` into the `RappFrameTransport` contract.
  ///
  /// Manages binary streaming over BLE L2CAP Connection-Oriented Channels,
  /// preserving 2-byte big-endian length-prefixed frame boundaries.
  public final class BleL2CAPChannelHandler: NSObject, StreamDelegate, RappFrameTransport,
    @unchecked Sendable
  {
    private enum Constants {
      static let readBufferSize = 4_096
    }

    private let channel: CBL2CAPChannel
    private let onEvent: @Sendable (BleRelayEvent) -> Void
    private let queue = DispatchQueue(label: "fi.refineid.ble-l2cap-handler")
    private var pending = Data()
    private var isClosed = false
    private var isInputOpen = false
    private var isOutputOpen = false

    /// Creates a handler wrapping the given open L2CAP channel.
    @preconcurrency
    public init(
      channel: CBL2CAPChannel,
      onEvent: @escaping @Sendable (BleRelayEvent) -> Void
    ) {
      self.channel = channel
      self.onEvent = onEvent
      super.init()
    }

    /// Starts processing input and output streams.
    public func start() {
      queue.async { [weak self] in
        guard let self else { return }
        guard let inputStream = channel.inputStream,
          let outputStream = channel.outputStream
        else {
          finish(with: .unreachable)
          return
        }

        inputStream.delegate = self
        outputStream.delegate = self

        CFReadStreamSetDispatchQueue(
          inputStream as CFReadStream,
          queue
        )
        CFWriteStreamSetDispatchQueue(
          outputStream as CFWriteStream,
          queue
        )

        inputStream.open()
        outputStream.open()
      }
    }

    /// Sends one opaque frame over the L2CAP output stream with length prefix framing.
    public func send(_ frame: Data) async throws {
      guard let encoded = BleRelayFraming.encode(frame) else {
        throw BleRelayTransportError.invalidFrameLength
      }

      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        queue.async { [weak self] in
          guard let self, !isClosed, let outputStream = channel.outputStream else {
            continuation.resume(throwing: BleRelayTransportError.notConnected)
            return
          }
          do {
            try writeBuffer(encoded, to: outputStream)
            continuation.resume()
          } catch {
            continuation.resume(throwing: error)
          }
        }
      }
    }

    private func writeBuffer(_ encoded: Data, to outputStream: OutputStream) throws {
      var totalWritten = 0
      let count = encoded.count

      try encoded.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
          throw BleRelayTransportError.send("Invalid buffer")
        }

        while totalWritten < count {
          let chunk = outputStream.write(
            baseAddress.advanced(by: totalWritten),
            maxLength: count - totalWritten
          )
          guard chunk > 0 else {
            if let error = outputStream.streamError {
              throw BleRelayTransportError.send(error.localizedDescription)
            }
            throw BleRelayTransportError.send("Write returned \(chunk)")
          }
          totalWritten += chunk
        }
      }
    }

    /// Closes the channel streams and marks the transport finished.
    public func close() async {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        queue.async { [weak self] in
          self?.finish(with: .cancelled)
          continuation.resume()
        }
      }
    }

    // MARK: - StreamDelegate

    /// Handles lifecycle and I/O readiness events from the input and output streams.
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
      let isInputStream = aStream === channel.inputStream
      let isOutputStream = aStream === channel.outputStream
      queue.async { [weak self] in
        guard let self, !isClosed else { return }

        switch eventCode {
        case .openCompleted:
          if isInputStream {
            isInputOpen = true
          } else if isOutputStream {
            isOutputOpen = true
          }
          if isInputOpen, isOutputOpen {
            onEvent(.connected)
          }

        case .hasBytesAvailable:
          if isInputStream {
            readAvailableBytes()
          }

        case .errorOccurred:
          finish(with: .disconnected)

        case .endEncountered:
          finish(with: .disconnected)

        default:
          break
        }
      }
    }

    private func readAvailableBytes() {
      guard let inputStream = channel.inputStream else { return }
      var buffer = [UInt8](repeating: 0, count: Constants.readBufferSize)

      while inputStream.hasBytesAvailable {
        let bytesRead = inputStream.read(&buffer, maxLength: buffer.count)
        if bytesRead > 0 {
          pending.append(buffer, count: bytesRead)
          drainFrames()
        } else if bytesRead < 0 {
          finish(with: .disconnected)
          return
        } else {
          break
        }
      }
    }

    private func drainFrames() {
      while true {
        guard pending.count >= BleRelayFraming.lengthPrefixByteCount else { return }
        let prefix = pending.prefix(BleRelayFraming.lengthPrefixByteCount)
        guard let length = BleRelayFraming.payloadByteCount(lengthPrefix: Data(prefix)) else {
          finish(with: .malformedFrame)
          return
        }
        let total = BleRelayFraming.lengthPrefixByteCount + length
        guard pending.count >= total else { return }
        let payload = pending.dropFirst(BleRelayFraming.lengthPrefixByteCount).prefix(length)
        pending = Data(pending.dropFirst(total))
        onEvent(.frame(Data(payload)))
      }
    }

    private func finish(with error: BleRelayTransportError) {
      guard !isClosed else { return }
      isClosed = true

      if let inputStream = channel.inputStream {
        inputStream.close()
        inputStream.delegate = nil
        CFReadStreamSetDispatchQueue(inputStream as CFReadStream, nil)
      }
      if let outputStream = channel.outputStream {
        outputStream.close()
        outputStream.delegate = nil
        CFWriteStreamSetDispatchQueue(outputStream as CFWriteStream, nil)
      }

      onEvent(.closed(error))
    }
  }
#endif
