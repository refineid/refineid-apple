// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine) && os(macOS)
  import Darwin
  import Foundation

  /// Low-level `AF_UNIX` socket configuration, bounded `connect`, and length-prefixed frame I/O.
  extension RappHeldSessionHandoff {
    /// Result of writing one length-prefixed frame over a connected socket.
    internal enum WriteOutcome {
      /// All header and payload bytes were written.
      case completed

      /// Peer closed the connection before the write finished.
      case disconnected

      /// Socket send timeout elapsed.
      case timedOut

      /// Any other low-level socket write error occurred.
      case failed
    }

    /// Result of reading one length-prefixed frame from a connected socket.
    internal enum ReadOutcome {
      /// One bounded frame was read in full.
      case message(Data)

      /// Peer closed the stream cleanly before sending a frame.
      case endOfStream

      /// Socket receive timeout elapsed while awaiting an answer.
      case timedOut

      /// Truncated stream, oversized frame header, or low-level socket error.
      case failed
    }

    private static let frameHeaderByteCount = 4
    private static let microsecondsPerSecond: Double = 1_000_000
    private static let microsecondsCarryThreshold: Int32 = 1_000_000
    private static let millisecondsPerSecond: Double = 1_000

    /// Builds a `sockaddr_un` for `path`, failing closed if `path` exceeds `sun_path` capacity.
    internal static func makeSocketAddress(path: String) -> sockaddr_un? {
      let utf8 = Array(path.utf8)
      var address = sockaddr_un()
      let capacity = MemoryLayout.size(ofValue: address.sun_path)
      guard !utf8.isEmpty, utf8.count < capacity else { return nil }
      address.sun_family = sa_family_t(AF_UNIX)
      address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
      withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
        for (index, byte) in utf8.enumerated() {
          rawBuffer[index] = byte
        }
        rawBuffer[utf8.count] = 0
      }
      return address
    }

    /// Normalizes a `TimeInterval` into a valid `timeval` (`0 <= tv_usec < 1_000_000`).
    internal static func normalizedTimeval(seconds: TimeInterval) -> timeval {
      let clamped = max(0, seconds)
      var wholeSeconds = Int(clamped.rounded(.down))
      var microseconds = Int32(
        ((clamped - Double(wholeSeconds)) * microsecondsPerSecond).rounded()
      )
      if microseconds >= microsecondsCarryThreshold {
        wholeSeconds += 1
        microseconds -= microsecondsCarryThreshold
      }
      if microseconds < 0 {
        microseconds = 0
      }
      return timeval(tv_sec: wholeSeconds, tv_usec: microseconds)
    }

    /// Creates a `SOCK_STREAM` Unix socket with `FD_CLOEXEC`, `SO_NOSIGPIPE`, and verified timeouts.
    internal static func makeConfiguredSocket(
      readTimeout: TimeInterval?,
      writeTimeout: TimeInterval?
    ) -> Int32 {
      let socketDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
      guard socketDescriptor != invalidDescriptor else { return invalidDescriptor }
      guard
        enableCloseOnExec(on: socketDescriptor),
        enableNoSigPipe(on: socketDescriptor)
      else {
        _ = Darwin.close(socketDescriptor)
        return invalidDescriptor
      }
      if let readTimeout,
        !setSocketTimeout(on: socketDescriptor, option: SO_RCVTIMEO, seconds: readTimeout)
      {
        _ = Darwin.close(socketDescriptor)
        return invalidDescriptor
      }
      if let writeTimeout,
        !setSocketTimeout(on: socketDescriptor, option: SO_SNDTIMEO, seconds: writeTimeout)
      {
        _ = Darwin.close(socketDescriptor)
        return invalidDescriptor
      }
      return socketDescriptor
    }

    /// Applies `FD_CLOEXEC`, `SO_NOSIGPIPE`, and bounded server timeouts to an accepted client socket.
    internal static func configureAcceptedSocket(_ socketDescriptor: Int32) -> Bool {
      enableCloseOnExec(on: socketDescriptor)
        && enableNoSigPipe(on: socketDescriptor)
        && setSocketTimeout(
          on: socketDescriptor,
          option: SO_RCVTIMEO,
          seconds: serverReadTimeoutSeconds
        )
        && setSocketTimeout(
          on: socketDescriptor,
          option: SO_SNDTIMEO,
          seconds: serverWriteTimeoutSeconds
        )
    }

    /// Connects `socketDescriptor` to `address` within `timeoutSeconds` using non-blocking `poll`.
    internal static func connectSocket(
      _ socketDescriptor: Int32,
      to address: sockaddr_un,
      timeoutSeconds: TimeInterval
    ) -> Bool {
      let originalFlags = Darwin.fcntl(socketDescriptor, F_GETFL, 0)
      guard
        originalFlags != -1,
        Darwin.fcntl(socketDescriptor, F_SETFL, originalFlags | O_NONBLOCK) == 0
      else {
        return false
      }
      defer { _ = Darwin.fcntl(socketDescriptor, F_SETFL, originalFlags) }
      var mutable = address
      let length = socklen_t(MemoryLayout<sockaddr_un>.size)
      while true {
        let result = withUnsafePointer(to: &mutable) { pointer in
          pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPointer in
            Darwin.connect(socketDescriptor, sockPointer, length)
          }
        }
        if result == 0 { return true }
        let connectError = errno
        if connectError == EINTR { continue }
        guard connectError == EINPROGRESS || connectError == EALREADY else {
          return false
        }
        return awaitNonBlockingConnect(socketDescriptor, timeoutSeconds: timeoutSeconds)
      }
    }

    /// Writes a 4-byte big-endian length header followed by `payload`.
    internal static func writeFramed(_ payload: Data, to socketDescriptor: Int32) -> WriteOutcome {
      guard !payload.isEmpty, payload.count <= maximumMessageByteCount else {
        return .failed
      }
      var bigEndianLength = UInt32(payload.count).bigEndian
      let header = withUnsafeBytes(of: &bigEndianLength) { Data($0) }
      var frame = Data(capacity: frameHeaderByteCount + payload.count)
      frame.append(header)
      frame.append(payload)
      return writeAll(frame, to: socketDescriptor)
    }

    /// Reads a 4-byte big-endian length header and bounded payload from `socketDescriptor`.
    internal static func readFramed(from socketDescriptor: Int32) -> ReadOutcome {
      switch readExact(
        byteCount: frameHeaderByteCount,
        from: socketDescriptor,
        allowCleanEmpty: true
      ) {
      case .endOfStream:
        return .endOfStream
      case .timedOut:
        return .timedOut
      case .failed:
        return .failed
      case .message(let header):
        let length = header.reduce(0) { ($0 << 8) | Int($1) }
        guard length > 0, length <= maximumMessageByteCount else {
          return .failed
        }
        return readExact(byteCount: length, from: socketDescriptor, allowCleanEmpty: false)
      }
    }

    private static func awaitNonBlockingConnect(
      _ socketDescriptor: Int32,
      timeoutSeconds: TimeInterval
    ) -> Bool {
      let deadline = Date().addingTimeInterval(max(0, timeoutSeconds))
      while true {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { return false }
        let timeoutMillis = Int32(
          min(Double(Int32.max), ceil(remaining * millisecondsPerSecond))
        )
        var descriptorEntry = pollfd(
          fd: socketDescriptor,
          events: Int16(POLLOUT),
          revents: 0
        )
        let ready = Darwin.poll(&descriptorEntry, 1, timeoutMillis)
        if ready < 0 {
          if errno == EINTR { continue }
          return false
        }
        guard ready > 0 else { return false }
        var socketError: Int32 = 0
        var errorLength = socklen_t(MemoryLayout<Int32>.size)
        guard
          Darwin.getsockopt(
            socketDescriptor,
            SOL_SOCKET,
            SO_ERROR,
            &socketError,
            &errorLength
          ) == 0
        else {
          return false
        }
        return socketError == 0
      }
    }

    private static func enableCloseOnExec(on socketDescriptor: Int32) -> Bool {
      let current = Darwin.fcntl(socketDescriptor, F_GETFD, 0)
      guard current != -1 else { return false }
      return Darwin.fcntl(socketDescriptor, F_SETFD, current | FD_CLOEXEC) == 0
    }

    private static func enableNoSigPipe(on socketDescriptor: Int32) -> Bool {
      var one: Int32 = 1
      return Darwin.setsockopt(
        socketDescriptor,
        SOL_SOCKET,
        SO_NOSIGPIPE,
        &one,
        socklen_t(MemoryLayout<Int32>.size)
      ) == 0
    }

    private static func setSocketTimeout(
      on socketDescriptor: Int32,
      option: Int32,
      seconds: TimeInterval
    ) -> Bool {
      var timeout = normalizedTimeval(seconds: seconds)
      return Darwin.setsockopt(
        socketDescriptor,
        SOL_SOCKET,
        option,
        &timeout,
        socklen_t(MemoryLayout<timeval>.size)
      ) == 0
    }

    private static func writeAll(_ data: Data, to socketDescriptor: Int32) -> WriteOutcome {
      var offset = 0
      return data.withUnsafeBytes { rawBuffer in
        guard let base = rawBuffer.baseAddress else { return .failed }
        while offset < data.count {
          let written = Darwin.write(
            socketDescriptor, base.advanced(by: offset), data.count - offset)
          if written > 0 {
            offset += written
            continue
          }
          if written == 0 {
            return .failed
          }
          let writeError = errno
          if writeError == EINTR { continue }
          if writeError == EAGAIN || writeError == EWOULDBLOCK { return .timedOut }
          if writeError == EPIPE || writeError == ECONNRESET { return .disconnected }
          return .failed
        }
        return .completed
      }
    }

    private static func readExact(
      byteCount: Int,
      from socketDescriptor: Int32,
      allowCleanEmpty: Bool
    ) -> ReadOutcome {
      var buffer = Data(count: byteCount)
      var offset = 0
      let failure: ReadOutcome? = buffer.withUnsafeMutableBytes { rawBuffer in
        guard let base = rawBuffer.baseAddress else { return .failed }
        while offset < byteCount {
          let count = Darwin.read(socketDescriptor, base.advanced(by: offset), byteCount - offset)
          if count > 0 {
            offset += count
            continue
          }
          if count == 0 {
            return (offset == 0 && allowCleanEmpty) ? .endOfStream : .failed
          }
          let readError = errno
          if readError == EINTR { continue }
          if readError == EAGAIN || readError == EWOULDBLOCK { return .timedOut }
          return .failed
        }
        return nil
      }
      return failure ?? .message(buffer)
    }
  }
#endif
