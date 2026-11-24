// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A credential-bearing command APDU, transmittable at most once.
///
/// Construction consumes the noncopyable PIN transmission(s); reading the
/// wire bytes consumes the command. The chain user entry -> PIN value ->
/// transmission -> this command -> one transport payload is linear and
/// compiler-enforced end to end: no step can be repeated, so a credential
/// can never be replayed after a timeout, reset, reconnect, or length
/// correction (Documentation/release-plan.md section 4.3).
///
/// Every builder takes the resolved reference numbering: it selects both
/// the reference byte and the credential block shape. The citizen card
/// compares a block right-padded to the stored length; the organization
/// card compares the typed digits at their own length, because its
/// EF.AOD publishes no padding and FINEID S1 v3.0 §3.5.1.1 makes any
/// other length a failed - and counted - comparison.
public struct CredentialBearingCommand: ~Copyable {
  private let encoded: Data

  /// VERIFY against the PIN1 reference (FINEID S1 v4.2 §3.5.2,
  /// S4-1 v3.1; FINEID S4-2 v4.0 §4.2 for the organization numbering).
  ///
  /// The data field is one credential block; `build` names the layout.
  public static func verifyPin1(
    _ transmission: consuming Pin1Transmission,
    references: CredentialReferenceSet
  ) -> Self {
    build(
      instruction: Iso7816Values.insVerify,
      parameter1: Iso7816Values.verifyModeP1,
      reference: references.reference(for: .pin1),
      credentials: [transmission.store],
      references: references
    )
  }

  /// VERIFY against the PIN2 reference (S1 v4.2 §3.5.2).
  ///
  /// Verified state persists for the session until SELECT or reset;
  /// callers verify immediately before the one signature and never rely
  /// on it afterwards.
  public static func verifyPin2(
    _ transmission: consuming Pin2Transmission,
    references: CredentialReferenceSet
  ) -> Self {
    build(
      instruction: Iso7816Values.insVerify,
      parameter1: Iso7816Values.verifyModeP1,
      reference: references.reference(for: .pin2),
      credentials: [transmission.store],
      references: references
    )
  }

  /// VERIFY of the unblock credential as its own object (FINEID S4-2
  /// v4.0 §4.3.2): the precondition the security-data-object tables set
  /// for RESET RETRY COUNTER on the organization card.
  ///
  /// The citizen card has no such command - its unblocking key rides
  /// inside the single RESET RETRY COUNTER data field instead.
  public static func verifyUnblockCredential(
    _ transmission: consuming PukTransmission,
    references: CredentialReferenceSet
  ) -> Self {
    build(
      instruction: Iso7816Values.insVerify,
      parameter1: Iso7816Values.verifyModeP1,
      reference: references.reference(for: .puk),
      credentials: [transmission.store],
      references: references
    )
  }

  /// CHANGE REFERENCE DATA against the PIN1 reference: the current
  /// credential block, then the new (S1 v4.2 §3.5.3; Idemia
  /// organizational cards specification §4.1.7).
  ///
  /// Success resets the retry counter to its maximum and clears the
  /// verified flag: the new PIN is set but not presented.
  public static func changePin1(
    current: consuming Pin1Transmission,
    new: consuming Pin1Transmission,
    references: CredentialReferenceSet
  ) -> Self {
    build(
      instruction: Iso7816Values.insChangeReferenceData,
      parameter1: Iso7816Values.changeCurrentThenNewP1,
      reference: references.reference(for: .pin1),
      credentials: [current.store, new.store],
      references: references
    )
  }

  /// CHANGE REFERENCE DATA against the PIN2 reference: the current
  /// credential block, then the new (S1 v4.2 §3.5.3).
  ///
  /// Success resets the retry counter to its maximum and clears the
  /// verified flag: the new PIN is set but not presented.
  public static func changePin2(
    current: consuming Pin2Transmission,
    new: consuming Pin2Transmission,
    references: CredentialReferenceSet
  ) -> Self {
    build(
      instruction: Iso7816Values.insChangeReferenceData,
      parameter1: Iso7816Values.changeCurrentThenNewP1,
      reference: references.reference(for: .pin2),
      credentials: [current.store, new.store],
      references: references
    )
  }

  /// RESET RETRY COUNTER against the PIN1 reference: the PUK block,
  /// then the new credential block (S1 v4.2 §3.5.4).
  ///
  /// The reset-and-replace mode both resets the target's counter and
  /// sets its new value. The command's reference names the target PIN;
  /// the PUK itself has none, being the card's one unblocking key. A
  /// wrong PUK counts down the PUK's own retry counter, and exhausting
  /// it is terminal for the card. This single-command form is the
  /// citizen card's; the organization card unblocks in two commands
  /// (`verifyUnblockCredential`, then `resetPin1AfterVerifiedUnblock`).
  public static func unblockPin1(
    puk: consuming PukTransmission,
    new: consuming Pin1Transmission,
    references: CredentialReferenceSet
  ) -> Self {
    build(
      instruction: Iso7816Values.insResetRetryCounter,
      parameter1: Iso7816Values.resetWithPukThenNewP1,
      reference: references.reference(for: .pin1),
      credentials: [puk.store, new.store],
      references: references
    )
  }

  /// RESET RETRY COUNTER against the PIN2 reference: the PUK block,
  /// then the new credential block (S1 v4.2 §3.5.4).
  ///
  /// Same semantics as the PIN1 form: the reference names the target,
  /// the PUK is implicit, and a wrong PUK spends the PUK's own
  /// counter.
  public static func unblockPin2(
    puk: consuming PukTransmission,
    new: consuming Pin2Transmission,
    references: CredentialReferenceSet
  ) -> Self {
    build(
      instruction: Iso7816Values.insResetRetryCounter,
      parameter1: Iso7816Values.resetWithPukThenNewP1,
      reference: references.reference(for: .pin2),
      credentials: [puk.store, new.store],
      references: references
    )
  }

  /// RESET RETRY COUNTER carrying only the new PIN1, after the unblock
  /// credential was verified as its own object (Idemia organizational
  /// cards specification §4.1.6; FINEID S4-2 v4.0 §4.3.2).
  public static func resetPin1AfterVerifiedUnblock(
    new: consuming Pin1Transmission,
    references: CredentialReferenceSet
  ) -> Self {
    build(
      instruction: Iso7816Values.insResetRetryCounter,
      parameter1: Iso7816Values.resetNewDataOnlyP1,
      reference: references.reference(for: .pin1),
      credentials: [new.store],
      references: references
    )
  }

  /// RESET RETRY COUNTER carrying only the new PIN2, after the unblock
  /// credential was verified as its own object (Idemia organizational
  /// cards specification §4.1.6; FINEID S4-2 v4.0 §4.3.2).
  public static func resetPin2AfterVerifiedUnblock(
    new: consuming Pin2Transmission,
    references: CredentialReferenceSet
  ) -> Self {
    build(
      instruction: Iso7816Values.insResetRetryCounter,
      parameter1: Iso7816Values.resetNewDataOnlyP1,
      reference: references.reference(for: .pin2),
      credentials: [new.store],
      references: references
    )
  }

  /// Builds the one wire form every credential command shares.
  ///
  /// Interindustry class, the instruction, its mode parameter, the
  /// credential reference, a length byte covering the blocks, then each
  /// credential in the numbering's block shape: right-padded with the
  /// pad byte to the stored length for the citizen card - which rejects
  /// any other padding - or the bare typed digits for the organization
  /// card, which stores no padding. The named constants in
  /// `Iso7816Values` and `FineidValues` are the single home of the
  /// actual bytes; the tests hold the assembled vectors.
  ///
  /// Local copies are best-effort zeroized; the Data is owned by the
  /// command and consumed exactly once.
  private static func build(
    instruction: UInt8,
    parameter1: UInt8,
    reference: UInt8,
    credentials: [ZeroizingDigitStore],
    references: CredentialReferenceSet
  ) -> Self {
    var blocks: [[UInt8]] = []
    var blockTotal = 0
    for credential in credentials {
      var block = credential.bytes
      if let padByte = references.pinPadByte {
        while block.count < FineidValues.pinStoredLength {
          block.append(padByte)
        }
      }
      blockTotal += block.count
      blocks.append(block)
    }
    var body: [UInt8] = [
      Iso7816Values.classInterindustry,
      instruction,
      parameter1,
      reference,
      UInt8(blockTotal),
    ]
    for index in blocks.indices {
      body.append(contentsOf: blocks[index])
      for blockIndex in blocks[index].indices {
        blocks[index][blockIndex] = 0
      }
    }
    let command = Self(encoded: Data(body))
    for index in body.indices {
      body[index] = 0
    }
    return command
  }

  /// Consumes the command into the bytes the transport sends.
  ///
  /// After this call the command no longer exists; retransmission
  /// requires a fresh user entry by construction.
  public consuming func intoTransportPayload() -> Data {
    #if DEBUG
      DebugCredentialWriteCeiling.consumePermitIfEnabled()
    #endif
    return encoded
  }
}
