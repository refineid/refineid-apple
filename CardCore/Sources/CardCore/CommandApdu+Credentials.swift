// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Credential-attribute GET DATA APDU constructors split from `CommandApdu.swift`.
extension CommandApdu {
  /// The counter-safe PIN-container query (FINEID S1 v4.2 section 3.15.2;
  /// GED24035 section 7.13).
  ///
  /// GET DATA `00 CB 00 FF 05 A0 03 83 01 ref 00`: reads the PIN
  /// container's attributes without presenting a credential and without
  /// touching any counter.
  public static func readCredentialAttributes(
    role: CredentialRole,
    references: CredentialReferenceSet
  ) -> Self {
    Self(
      encoded: Data([
        Iso7816Values.classInterindustry,
        Iso7816Values.insGetData,
        FineidValues.pinContainerP1,
        FineidValues.pinContainerP2,
        FineidValues.pinContainerRequestLength,
        FineidValues.pinContainerTemplateTag,
        FineidValues.pinContainerTemplateLength,
        FineidValues.pinReferenceTag,
        FineidValues.pinReferenceLength,
        references.reference(for: role),
        0,
      ])
    )
  }

  /// The counter-safe PIN-container query under the FINEID citizen numbering.
  public static func readCredentialAttributes(role: CredentialRole) -> Self {
    readCredentialAttributes(role: role, references: .citizen)
  }
}
