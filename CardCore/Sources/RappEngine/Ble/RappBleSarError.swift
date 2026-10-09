// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A fragment or message the RAPP v26.10.1 §5.3 SAR layer refuses.
///
/// Every receive failure is unrecoverable: the reassembly buffer is zeroized
/// and the connection must be dropped.
public enum RappBleSarError: Error, Equatable, Sendable {
  /// The negotiated ATT MTU is below the profile minimum of 512 bytes.
  case attMtuTooSmall
  /// A fragment carries no payload.
  case emptyFragment
  /// A FIRST fragment already carries the whole declared total.
  case firstFragmentNotShorterThanTotal
  /// A FIRST fragment carries fewer than 64 bytes.
  case firstFragmentTooShort
  /// A fragment carries more payload than the capacity allows.
  case fragmentOverCapacity
  /// Fewer bytes than one SAR header.
  case headerTruncated
  /// The flags are not FIRST, CONT, LAST, or SINGLE.
  case illegalFlags
  /// FIRST or SINGLE arrived while a frame was being reassembled.
  case illegalTransition
  /// LAST arrived before the declared total was reached.
  case incompleteAtLast
  /// The payload capacity cannot carry a non-final fragment.
  case invalidCapacity
  /// The message is empty or longer than the 16-bit total length allows.
  case invalidMessageLength
  /// A CONT fragment carries fewer than 64 bytes.
  case nonFinalFragmentTooShort
  /// The fragment would take the frame past its declared total.
  case overflow
  /// The frame did not complete within 5.0 seconds of its FIRST fragment.
  case reassemblyTimeout
  /// The reserved byte or reserved flag bits are not zero.
  case reservedBitsSet
  /// The chunk sequence is not the next expected one.
  case sequenceMismatch
  /// The chunk sequence is 1024 or above.
  case sequenceOutOfBounds
  /// A SINGLE fragment's payload differs from its declared total.
  case singleLengthMismatch
  /// The declared total differs from the one the frame latched.
  case totalLengthChanged
  /// A frame does not begin with FIRST or SINGLE at sequence zero.
  case unexpectedInitialFragment
  /// The declared total frame length is zero.
  case zeroTotalLength
}
