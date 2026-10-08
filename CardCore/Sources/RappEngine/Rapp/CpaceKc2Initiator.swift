// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// The requester's side after sending Y_A.
internal struct CpaceKc2Initiator {
  private let scalar: Data
  private let sid: Data
  private let context: Data

  /// Y_A, the 32-byte step 1 message.
  internal let stepOne: Data

  internal init(code: String, context: Data, offerIdentifier: Data, randomBytes: Data) throws {
    let generator = try cpaceKc2Generator(code: code, context: context, sid: offerIdentifier)
    scalar = try cpaceSampleScalar(randomBytes)
    sid = offerIdentifier
    self.context = context
    stepOne = generator.scalarMul(scalar).compress()
  }

  /// Verifies Y_B and T_B, returning T_A and the pre-shared key.
  internal func processStepTwo(_ message: Data) throws -> (stepThree: Data, presharedKey: Data) {
    guard message.count == RappCpaceConstants.step2Size else {
      throw RappCpaceError.malformedFrame
    }
    let partyBPublic = Data(message.prefix(RappCpaceConstants.pointSize))
    let responderTag = Data(message.suffix(RappCpaceConstants.tagSize))
    let peer = try cpacePeerPoint(partyBPublic)
    let keys = cpaceKc2Keys(
      sid: sid, context: context, sharedPoint: try cpaceSharedPoint(peer, scalar: scalar),
      partyAPublic: stepOne, partyBPublic: partyBPublic)
    guard cpaceTagsMatch(keys.responderTag, responderTag) else {
      throw RappCpaceError.confirmationTagMismatch
    }
    return (keys.initiatorTag, keys.presharedKey)
  }
}
