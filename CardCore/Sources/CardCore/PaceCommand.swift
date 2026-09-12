// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The two command APDUs a PACE run sends.
///
/// They live apart from `CommandApdu` on purpose. That type documents itself
/// as the read-only, idempotent command class -- safe to retransmit, no side
/// effect on any counter. These two are neither: MSE:Set AT and GENERAL
/// AUTHENTICATE advance a protocol state machine inside the card, and
/// resending one out of order aborts the run. Keeping them in their own,
/// internal home means the safety class of a command stays readable from its
/// type, and nothing outside PACE can reach them.
///
/// Provenance: the command builders inside the RefineID iOS browser donor
/// `Sources/RefineIDBrowserKit/Card/Pace.swift`.
internal enum PaceCommand {
  /// The largest data field a short-form command APDU can carry.
  private static let maximumDataLength: Int = 255

  /// `Le = 00`, the short-form maximum every GENERAL AUTHENTICATE asks for.
  private static let maximumExpectedLength = ExpectedResponseLength(
    count: ExpectedResponseLength.maximum
  )

  /// MSE:Set AT naming the PACE suite, the CAN as the password, and
  /// brainpoolP384r1 as the domain parameters.
  ///
  /// Nil only if the assembled template does not fit a short-form data
  /// field, which the fixed contents make impossible; the failable shape
  /// exists so no encoder result is force unwrapped.
  internal static func securityEnvironment() -> Data? {
    guard
      let mechanism = DerTlvRecord.encoded(
        tag: PaceValues.cryptographicMechanismReferenceTag,
        value: Data(PaceValues.protocolOidBody)
      ),
      let password = DerTlvRecord.encoded(
        tag: PaceValues.passwordReferenceTag,
        value: Data([PaceValues.passwordReferenceCan])
      ),
      let domain = DerTlvRecord.encoded(
        tag: PaceValues.domainParameterReferenceTag,
        value: Data([PaceValues.domainParameterReferenceBrainpoolP384r1])
      )
    else {
      return nil
    }
    return Self.bytes(
      header: Data([
        Iso7816Values.classInterindustry,
        Iso7816Values.insManageSecurityEnvironment,
        PaceValues.mseSetAuthenticationTemplateP1,
        PaceValues.mseSetAuthenticationTemplateP2,
      ]),
      data: mechanism + password + domain,
      expectedLength: nil
    )
  }

  /// One GENERAL AUTHENTICATE carrying an already-encoded `7C` template.
  ///
  /// `classByte` selects chaining: the first three rounds set the chaining
  /// bit, the last one clears it, and that is how the card learns the
  /// exchange is over.
  internal static func generalAuthenticate(template: Data, classByte: UInt8) -> Data? {
    guard let expectedLength = Self.maximumExpectedLength else { return nil }
    return Self.bytes(
      header: Data([
        classByte,
        PaceValues.insGeneralAuthenticate,
        PaceValues.generalAuthenticateP1,
        PaceValues.generalAuthenticateP2,
      ]),
      data: template,
      expectedLength: expectedLength
    )
  }

  /// A short-form command APDU, or nil when the data field does not fit.
  private static func bytes(
    header: Data,
    data: Data,
    expectedLength: ExpectedResponseLength?
  ) -> Data? {
    guard !data.isEmpty, data.count <= Self.maximumDataLength else { return nil }
    var command = header
    command.append(UInt8(data.count))
    command.append(data)
    if let expectedLength {
      command.append(expectedLength.encodedByte)
    }
    return command
  }
}
