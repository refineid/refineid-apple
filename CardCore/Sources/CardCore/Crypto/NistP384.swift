// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// NIST P-384 (`secp384r1`).
///
/// FIPS 186-4 appendix D.1.2.4 and SEC 2 v2 section 2.5.1; standardized
/// domain parameter 15 (BSI TR-03110-3 table 4). The organization cards
/// publish it (FINEID S4-2 v4.0 section 6).
public enum NistP384: PaceCurve {
  /// The parameters of FIPS 186-4 appendix D.1.2.4.
  public static let parameters = CurveDomainParameters(
    prime: NistP384Values.prime,
    coefficientA: NistP384Values.coefficientA,
    coefficientB: NistP384Values.coefficientB,
    generatorX: NistP384Values.generatorX,
    generatorY: NistP384Values.generatorY,
    order: NistP384Values.order,
    coordinateByteCount: NistP384Values.coordinateByteCount
  )
}
