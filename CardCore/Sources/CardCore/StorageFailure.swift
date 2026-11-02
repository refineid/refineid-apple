// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// Tells a write the system refused for lack of space from every other
/// storage failure.
///
/// Only the system's own out-of-space codes count: the keychain's
/// `errSecDiskFull`, POSIX `ENOSPC` and Foundation's
/// `NSFileWriteOutOfSpaceError`, found on the error itself or anywhere in
/// its `NSUnderlyingErrorKey` chain. A generic input/output status says
/// nothing about space, so it counts only when an underlying error in its
/// chain names one of these codes.
public enum StorageFailure: Error, Equatable, Sendable {
  /// The system refused a write for lack of space.
  case outOfSpace

  /// How many underlying errors are followed before the chain is taken
  /// to name no out-of-space code.
  private static let maximumChainDepth = 8

  /// Whether the keychain refused a write for lack of space.
  public static func isOutOfSpace(_ status: OSStatus) -> Bool {
    status == errSecDiskFull
  }

  /// Whether `error`, or an error it wraps, reports that the disk is full.
  public static func isOutOfSpace(_ error: any Error) -> Bool {
    if error as? Self == .outOfSpace {
      return true
    }
    if case RappDeviceVault.Failure.unavailable(let status) = error {
      return isOutOfSpace(status)
    }
    var current: NSError? = error as NSError
    var depth = 0
    while let examined = current, depth <= maximumChainDepth {
      if names(examined) { return true }
      current = examined.userInfo[NSUnderlyingErrorKey] as? NSError
      depth += 1
    }
    return false
  }

  /// Whether this one error, not its chain, carries an out-of-space code.
  private static func names(_ error: NSError) -> Bool {
    switch error.domain {
    case NSOSStatusErrorDomain:
      OSStatus(exactly: error.code).map(isOutOfSpace) ?? false

    case NSPOSIXErrorDomain:
      error.code == Int(POSIXErrorCode.ENOSPC.rawValue)

    case NSCocoaErrorDomain:
      error.code == CocoaError.Code.fileWriteOutOfSpace.rawValue

    default:
      false
    }
  }
}
