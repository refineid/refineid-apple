// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

extension EstonianEidTestFixture {
  internal static func estonian2025DiscoveryExchanges(plainRead: Data) -> [(Data, Data)] {
    [
      (selectEf(.objectDirectory), status(.success)),
      (plainRead, response(objectDirectory(), status: .success)),
      (selectEf(certificateDirectoryFile), status(.success)),
      (plainRead, response(certificateDirectory(), status: .success)),
      (selectEf(privateKeyDirectoryFile), status(.success)),
      (plainRead, response(privateKeyDirectory(), status: .success)),
    ]
  }

  internal static func expectStandardEstonianPinLengths(_ lengths: CardPinLengths) {
    #expect(
      lengths.pin1.accepted
        == PasswordLengthRange(minimum: Pin1.minimumDigitCount, maximum: Pin1.maximumDigitCount)
    )
    #expect(
      lengths.pin2.accepted
        == PasswordLengthRange(
          minimum: EstonianEidValues.pin2MinimumDigitCount,
          maximum: Pin2.maximumDigitCount
        )
    )
    #expect(
      lengths.puk.accepted
        == PasswordLengthRange(minimum: Puk.minimumDigitCount, maximum: Puk.maximumDigitCount)
    )
  }

  internal static func verifyPin1Payload(
    _ digits: String,
    references: CredentialReferenceSet
  ) -> Data {
    guard let pin = Pin1(digits: digits) else {
      preconditionFailure("invalid synthetic PIN1")
    }
    let command = CredentialBearingCommand.verifyPin1(
      pin.consumeForSingleTransmission(), references: references
    )
    return command.intoTransportPayload()
  }

  internal static func verifyPin2Payload(
    _ digits: String,
    references: CredentialReferenceSet
  ) -> Data {
    guard let pin = Pin2(digits: digits) else {
      preconditionFailure("invalid synthetic PIN2")
    }
    let command = CredentialBearingCommand.verifyPin2(
      pin.consumeForSingleTransmission(), references: references
    )
    return command.intoTransportPayload()
  }

  internal static func changePin1Payload(
    current: String,
    new: String,
    references: CredentialReferenceSet
  ) -> Data {
    guard let oldPin = Pin1(digits: current), let freshPin = Pin1(digits: new) else {
      preconditionFailure("invalid synthetic PIN1")
    }
    let command = CredentialBearingCommand.changePin1(
      current: oldPin.consumeForSingleTransmission(),
      new: freshPin.consumeForSingleTransmission(),
      references: references
    )
    return command.intoTransportPayload()
  }

  internal static func changePin2Payload(
    current: String,
    new: String,
    references: CredentialReferenceSet
  ) -> Data {
    guard let oldPin = Pin2(digits: current), let freshPin = Pin2(digits: new) else {
      preconditionFailure("invalid synthetic PIN2")
    }
    let command = CredentialBearingCommand.changePin2(
      current: oldPin.consumeForSingleTransmission(),
      new: freshPin.consumeForSingleTransmission(),
      references: references
    )
    return command.intoTransportPayload()
  }

  internal static func unblockPin1Payload(
    puk: String,
    new: String,
    references: CredentialReferenceSet
  ) -> Data {
    guard let pukValue = Puk(digits: puk), let freshPin = Pin1(digits: new) else {
      preconditionFailure("invalid synthetic unblock credentials")
    }
    let command = CredentialBearingCommand.unblockPin1(
      puk: pukValue.consumeForSingleTransmission(),
      new: freshPin.consumeForSingleTransmission(),
      references: references
    )
    return command.intoTransportPayload()
  }

  internal static func unblockPin2Payload(
    puk: String,
    new: String,
    references: CredentialReferenceSet
  ) -> Data {
    guard let pukValue = Puk(digits: puk), let freshPin = Pin2(digits: new) else {
      preconditionFailure("invalid synthetic unblock credentials")
    }
    let command = CredentialBearingCommand.unblockPin2(
      puk: pukValue.consumeForSingleTransmission(),
      new: freshPin.consumeForSingleTransmission(),
      references: references
    )
    return command.intoTransportPayload()
  }

  internal static func verifyPukPayload(
    _ digits: String,
    references: CredentialReferenceSet
  ) -> Data {
    guard let puk = Puk(digits: digits) else {
      preconditionFailure("invalid synthetic PUK")
    }
    let command = CredentialBearingCommand.verifyUnblockCredential(
      puk.consumeForSingleTransmission(), references: references
    )
    return command.intoTransportPayload()
  }

  internal static func resetPin1Payload(
    _ digits: String,
    references: CredentialReferenceSet
  ) -> Data {
    guard let pin = Pin1(digits: digits) else {
      preconditionFailure("invalid synthetic PIN1")
    }
    let command = CredentialBearingCommand.resetPin1AfterVerifiedUnblock(
      new: pin.consumeForSingleTransmission(), references: references
    )
    return command.intoTransportPayload()
  }

  internal static func resetPin2Payload(
    _ digits: String,
    references: CredentialReferenceSet
  ) -> Data {
    guard let pin = Pin2(digits: digits) else {
      preconditionFailure("invalid synthetic PIN2")
    }
    let command = CredentialBearingCommand.resetPin2AfterVerifiedUnblock(
      new: pin.consumeForSingleTransmission(), references: references
    )
    return command.intoTransportPayload()
  }
}
