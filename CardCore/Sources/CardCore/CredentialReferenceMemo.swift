// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Session-scoped memory of the credential reference numbering the card
/// answered to, so one resolution serves every later command.
///
/// A reference type on purpose: `CardOperations` is a value that may be
/// handed around within one exclusive session, and the numbering is a
/// property of the card behind the session, not of any one copy of the
/// operations value. The memo is written by whichever operation resolves
/// first and read by everything after it - including the signing chain,
/// which must pick the organization form without adding a probe of its
/// own.
internal final class CredentialReferenceMemo {
  /// The numbering the card confirmed, or nil before the first probe.
  internal var resolved: CredentialReferenceSet?

  /// Probed retry counter outcomes per role, cached for the lifetime of this session.
  internal var probedRetryCounters: [CredentialRole: RetryProbeOutcome] = [:]

  /// The PACE suite password states are read under, once per session.
  internal var passwordStateSuite: PaceInfo?

  /// The IAS-ECC root AID that answered on an EstEID 2018 card (Cosmo v8 or Cosmo X).
  internal var estonian2018Aid: ApplicationIdentifier?

  /// Live PKCS#15 certificate paths discovered from EF.OD / EF.CD / EF.PrKD, once per session.
  internal var discoveredCertificatePaths: [CertificateSlot: [FileIdentifier]] = [:]

  /// Live PKCS#15 key references discovered from EF.PrKD, once per session.
  internal var discoveredKeyReferences: [CardSigningKey: UInt8] = [:]

  /// Whether PKCS#15 directory discovery has already been attempted in this session.
  internal var attemptedDirectoryDiscovery = false

  /// The EF.AOD file identifier discovered from EF.OD, when present.
  internal var discoveredAodFile: FileIdentifier?
}
