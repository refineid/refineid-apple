// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// The custodian's side after answering Y_A, awaiting T_A.
internal struct CpaceKc2Responder {
  private let expectedInitiatorTag: Data
  private let presharedKey: Data

  /// Y_B followed by T_B, the 64-byte step 2 message.
  internal let stepTwo: Data

  internal init(
    code: String, context: Data, offerIdentifier: Data, stepOne: Data, randomBytes: Data
  ) throws {
    guard stepOne.count == RappCpaceConstants.step1Size else {
      throw RappCpaceError.malformedFrame
    }
    let peer = try cpacePeerPoint(stepOne)
    let generator = try cpaceKc2Generator(code: code, context: context, sid: offerIdentifier)
    let scalar = try cpaceSampleScalar(randomBytes)
    let partyBPublic = generator.scalarMul(scalar).compress()
    let keys = cpaceKc2Keys(
      sid: offerIdentifier, context: context,
      sharedPoint: try cpaceSharedPoint(peer, scalar: scalar),
      partyAPublic: stepOne, partyBPublic: partyBPublic)
    expectedInitiatorTag = keys.initiatorTag
    presharedKey = keys.presharedKey
    stepTwo = partyBPublic + keys.responderTag
  }

  /// Verifies T_A, returning the pre-shared key.
  internal func processStepThree(_ message: Data) throws -> Data {
    guard message.count == RappCpaceConstants.step3Size else {
      throw RappCpaceError.malformedFrame
    }
    guard cpaceTagsMatch(expectedInitiatorTag, message) else {
      throw RappCpaceError.confirmationTagMismatch
    }
    return presharedKey
  }
}
