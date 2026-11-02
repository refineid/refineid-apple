// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security
import Testing

@testable import CardCore

#if canImport(RappEngine)
  import RappEngine
#endif

/// Only the system's own out-of-space codes read as a full disk, on the
/// error itself or anywhere in its underlying chain.
@Suite
internal struct StorageFailureTests {
  /// An error domain that names no system storage failure.
  private static let unrelatedDomain = "fi.refineid.test.unrelated"

  /// A code in the unrelated domain.
  private static let unrelatedCode = 1

  private static var keychainFull: NSError {
    NSError(domain: NSOSStatusErrorDomain, code: Int(errSecDiskFull))
  }

  private static var posixFull: NSError {
    NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXErrorCode.ENOSPC.rawValue))
  }

  private static var cocoaFull: NSError {
    NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileWriteOutOfSpace.rawValue)
  }

  /// `inner` wrapped as the underlying error of an error in `domain`.
  private static func wrapping(_ inner: NSError, in domain: String, code: Int) -> NSError {
    NSError(domain: domain, code: code, userInfo: [NSUnderlyingErrorKey: inner])
  }

  /// A vault call the keychain refused with `status`.
  private static func refuse(_ status: OSStatus) throws {
    throw RappDeviceVault.Failure.unavailable(status)
  }

  @Test
  internal func theKeychainFullStatusIsOutOfSpace() {
    #expect(StorageFailure.isOutOfSpace(errSecDiskFull))
  }

  @Test
  internal func otherKeychainStatusesAreNot() {
    for status in [errSecSuccess, errSecIO, errSecParam, errSecDuplicateItem, errSecItemNotFound] {
      #expect(!StorageFailure.isOutOfSpace(status))
    }
  }

  @Test
  internal func eachSystemOutOfSpaceErrorIsOutOfSpace() {
    for error in [Self.keychainFull, Self.posixFull, Self.cocoaFull] {
      #expect(StorageFailure.isOutOfSpace(error), "\(error.domain)")
    }
    #expect(StorageFailure.isOutOfSpace(POSIXError(.ENOSPC)))
    #expect(StorageFailure.isOutOfSpace(CocoaError(.fileWriteOutOfSpace)))
    #expect(StorageFailure.isOutOfSpace(StorageFailure.outOfSpace))
  }

  @Test
  internal func aVaultRefusedForSpaceIsOutOfSpace() {
    #expect(StorageFailure.isOutOfSpace(RappDeviceVault.Failure.unavailable(errSecDiskFull)))
    #expect(!StorageFailure.isOutOfSpace(RappDeviceVault.Failure.unavailable(errSecIO)))
    #expect(!StorageFailure.isOutOfSpace(RappDeviceVault.Failure.notFound))
  }

  @Test
  internal func aFullDiskUnderAnotherErrorIsOutOfSpace() {
    let inputOutput = NSError(domain: NSOSStatusErrorDomain, code: Int(errSecIO))
    #expect(!StorageFailure.isOutOfSpace(inputOutput))
    let ioCarryingSpace = Self.wrapping(
      Self.posixFull, in: NSOSStatusErrorDomain, code: Int(errSecIO))
    #expect(StorageFailure.isOutOfSpace(ioCarryingSpace))
    let twoDeep = Self.wrapping(
      Self.wrapping(Self.cocoaFull, in: Self.unrelatedDomain, code: Self.unrelatedCode),
      in: Self.unrelatedDomain, code: Self.unrelatedCode)
    #expect(StorageFailure.isOutOfSpace(twoDeep))
  }

  @Test
  internal func otherErrorsAreNot() {
    let others: [any Error] = [
      NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXErrorCode.EIO.rawValue)),
      NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXErrorCode.EDQUOT.rawValue)),
      CocoaError(.fileWriteNoPermission),
      CocoaError(.fileWriteUnknown),
      NSError(domain: Self.unrelatedDomain, code: Int(POSIXErrorCode.ENOSPC.rawValue)),
      Self.wrapping(
        NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileWriteNoPermission.rawValue),
        in: Self.unrelatedDomain, code: Self.unrelatedCode),
    ]
    for error in others {
      #expect(!StorageFailure.isOutOfSpace(error), "\(error)")
    }
  }

  #if canImport(RappEngine)
    @Test
    internal func aPairingWriteRefusedForSpaceEndsOutOfSpace() {
      let witness = RappVaultWriteWitness(vault: RappDeviceVault(accessGroup: nil))
      #expect(witness.closeReason == .persistenceFailure)
      #expect(throws: RappVaultError.Unavailable) {
        try witness.witnessing { try Self.refuse(errSecDiskFull) }
      }
      #expect(witness.closeReason == .outOfSpace)
    }

    @Test
    internal func aPairingWriteRefusedOtherwiseEndsAsBefore() {
      let witness = RappVaultWriteWitness(vault: RappDeviceVault(accessGroup: nil))
      #expect(throws: RappVaultError.Unavailable) {
        try witness.witnessing { try Self.refuse(errSecIO) }
      }
      #expect(witness.closeReason == .persistenceFailure)
    }
  #endif
}
