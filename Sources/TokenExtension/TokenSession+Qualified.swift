// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

@_spi(TokenExtension) import CardCore
// swiftlint:disable:previous attributes
import CryptoTokenKit
import Foundation

/// The qualified-signature route: split from the session for length,
/// and because it shares nothing with the PIN1 paths but the
/// transport.
extension TokenSession {
  /// The qualified signature, reader interfaces only.
  ///
  /// A deadline field has no room for the probe-verify-sign chain and
  /// no qualified key is ever published from a prime, so reaching this
  /// with one is a system inconsistency answered with tokenNotFound.
  internal func qualifiedThroughReader(
    token: Token,
    dataToSign: Data,
    algorithm: TKTokenKeyAlgorithm
  ) throws -> Data {
    guard
      let profile = token.signKeyProfile,
      let signPublicKey = token.signLeafPublicKey,
      token.interface != .fieldWithDeadline
    else {
      throw TKError(.tokenNotFound)
    }
    guard
      let request = SigningAlgorithmResolver.resolve(
        algorithm,
        input: dataToSign,
        profile: profile
      )
    else {
      TokenLog.error("sign: no matching qualified algorithm - returning badParameter")
      throw TKError(.badParameter)
    }
    let entered = collectedPin2
    collectedPin2 = nil
    TokenLog.info(
      "sign: qualified entry pin2Collected=\(entered != nil) "
        + "session=\(UInt(bitPattern: ObjectIdentifier(self).hashValue))"
    )
    let smartCard = try requestedSmartCard()
    do {
      let signature = try SmartCardChannel(smartCard, waits: .reader).withSession { channel in
        try QualifiedSignature.perform(
          on: QualifiedSignature.ChannelAccess(
            channel: channel,
            unsealing: token.unsealing
          ),
          enteredPin: entered,
          request: request,
          signPublicKey: signPublicKey,
          token: token
        )
      }
      TokenLog.trace("sign: qualified path produced \(signature.count) DER bytes")
      return signature
    } catch let error as TokenError {
      TokenLog.error("sign: qualified failed \(error)")
      throw error.asTKError
    } catch let error as CardOperationError {
      TokenLog.error("sign: qualified card failed \(error)")
      throw TKError(.communicationError)
    } catch {
      // A PACE refusal, a secure-messaging fault or a transport timeout
      // is not a wrong PIN: map it so ctkd ends the operation instead of
      // re-looping the prompt.
      TokenLog.error("sign: qualified failed unmapped \(error)")
      throw TKError(.communicationError)
    }
  }
}
