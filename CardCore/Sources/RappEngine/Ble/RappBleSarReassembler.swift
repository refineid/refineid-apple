// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The normative SAR receive state machine (RAPP v26.10.9 §5.3), for one
/// connection and one direction.
///
/// Fragments must be handed over in arrival order. Any refused fragment
/// zeroizes the buffer and returns the machine to idle; the caller then
/// drops the connection. The clock is the caller's monotonic milliseconds.
public struct RappBleSarReassembler: Sendable {
  private struct Header {
    let total: Int
    let sequence: Int
    let flags: UInt8
  }

  private var expectedSequence = 0
  private var expectedTotal = 0
  private var buffer: [UInt8] = []
  private var deadline: UInt64?

  /// Whether no frame is being reassembled.
  public var isIdle: Bool {
    expectedSequence == 0 && buffer.isEmpty
  }

  /// A machine waiting for the first fragment of a frame.
  public init() {
    // An idle machine holds nothing.
  }

  /// Checks the rules every fragment must meet before any state is used.
  private static func header(_ fragment: Data, capacity: Int) throws -> Header {
    guard fragment.count >= RappBleSar.headerSize else { throw RappBleSarError.headerTruncated }
    let flags = fragment[fragment.startIndex + RappBleSar.Field.flags]
    guard fragment[fragment.startIndex + RappBleSar.Field.reserved] == 0 else {
      throw RappBleSarError.reservedBitsSet
    }
    guard
      [
        RappBleSar.Flag.first, RappBleSar.Flag.continuation, RappBleSar.Flag.last,
        RappBleSar.Flag.single,
      ].contains(flags)
    else {
      throw flags & ~RappBleSar.Flag.allDefined == 0
        ? RappBleSarError.illegalFlags : RappBleSarError.reservedBitsSet
    }
    let payloadCount = fragment.count - RappBleSar.headerSize
    guard payloadCount > 0 else { throw RappBleSarError.emptyFragment }
    guard payloadCount <= capacity else { throw RappBleSarError.fragmentOverCapacity }
    let sequence = RappBleSar.field(fragment, at: RappBleSar.Field.sequence)
    guard sequence < RappBleSar.sequenceLimit else { throw RappBleSarError.sequenceOutOfBounds }
    let total = RappBleSar.field(fragment, at: RappBleSar.Field.totalLength)
    guard total > 0 else { throw RappBleSarError.zeroTotalLength }
    return Header(total: total, sequence: sequence, flags: flags)
  }

  /// Consumes one fragment.
  ///
  /// - Returns: the complete message once its last fragment arrives, or nil
  ///   while more fragments are expected.
  /// - Throws: ``RappBleSarError`` for any fragment the specification
  ///   refuses; the machine is then idle and zeroized.
  public mutating func receive(
    _ fragment: Data, capacity: Int, nowMilliseconds: UInt64
  ) throws -> Data? {
    do {
      return try accept(Data(fragment), capacity: capacity, now: nowMilliseconds)
    } catch {
      reset()
      throw error
    }
  }

  /// Refuses a frame whose 5.0-second reassembly timer has run out.
  ///
  /// - Throws: ``RappBleSarError/reassemblyTimeout`` when a frame is in
  ///   progress and its deadline has passed; the machine is then idle.
  public mutating func checkTimer(nowMilliseconds: UInt64) throws {
    guard let deadline, nowMilliseconds >= deadline else { return }
    reset()
    throw RappBleSarError.reassemblyTimeout
  }

  /// Zeroizes any partial frame and returns to idle.
  public mutating func reset() {
    for index in buffer.indices {
      buffer[index] = 0
    }
    buffer.removeAll()
    expectedSequence = 0
    expectedTotal = 0
    deadline = nil
  }

  private mutating func accept(_ fragment: Data, capacity: Int, now: UInt64) throws -> Data? {
    try checkTimer(nowMilliseconds: now)
    let header = try Self.header(fragment, capacity: capacity)
    let payload = fragment.dropFirst(RappBleSar.headerSize)
    if isIdle {
      return try begin(header, payload: payload, now: now)
    }
    return try continueFrame(header, payload: payload)
  }

  /// Steps 2 to 7 for the first fragment of a frame.
  private mutating func begin(
    _ header: Header, payload: Data, now: UInt64
  ) throws -> Data? {
    guard header.flags == RappBleSar.Flag.first || header.flags == RappBleSar.Flag.single,
      header.sequence == 0
    else { throw RappBleSarError.unexpectedInitialFragment }
    if header.flags == RappBleSar.Flag.single {
      guard header.total == payload.count else { throw RappBleSarError.singleLengthMismatch }
      return Data(payload)
    }
    guard payload.count >= RappBleSar.minimumNonFinalPayload else {
      throw RappBleSarError.firstFragmentTooShort
    }
    guard payload.count < header.total else {
      throw RappBleSarError.firstFragmentNotShorterThanTotal
    }
    expectedTotal = header.total
    buffer.reserveCapacity(header.total)
    buffer.append(contentsOf: payload)
    expectedSequence = 1
    let (end, overflow) = now.addingReportingOverflow(RappBleSar.reassemblyTimeoutMilliseconds)
    deadline = overflow ? UInt64.max : end
    return nil
  }

  /// Steps 3 to 7 for every later fragment.
  private mutating func continueFrame(
    _ header: Header, payload: Data
  ) throws -> Data? {
    let isLast = header.flags == RappBleSar.Flag.last
    guard isLast || header.flags == RappBleSar.Flag.continuation else {
      throw RappBleSarError.illegalTransition
    }
    guard header.total == expectedTotal else { throw RappBleSarError.totalLengthChanged }
    guard header.sequence == expectedSequence else { throw RappBleSarError.sequenceMismatch }
    guard isLast || payload.count >= RappBleSar.minimumNonFinalPayload else {
      throw RappBleSarError.nonFinalFragmentTooShort
    }
    guard buffer.count + payload.count <= expectedTotal else { throw RappBleSarError.overflow }
    buffer.append(contentsOf: payload)
    guard isLast else {
      expectedSequence += 1
      return nil
    }
    guard buffer.count == expectedTotal else { throw RappBleSarError.incompleteAtLast }
    let message = Data(buffer)
    reset()
    return message
  }
}
