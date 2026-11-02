// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// NIST P-256 (`secp256r1`).
///
/// FIPS 186-4 appendix D.1.2.3 and SEC 2 v2 section 2.4.2; standardized
/// domain parameter 12 (BSI TR-03110-3 table 4). The organization cards
/// publish it (FINEID S4-2 v4.0 section 6).
public enum NistP256: PaceCurve {
  /// The parameters of FIPS 186-4 appendix D.1.2.3.
  public static let parameters = CurveDomainParameters(
    prime: NistP256Values.prime,
    coefficientA: NistP256Values.coefficientA,
    coefficientB: NistP256Values.coefficientB,
    generatorX: NistP256Values.generatorX,
    generatorY: NistP256Values.generatorY,
    order: NistP256Values.order,
    coordinateByteCount: NistP256Values.coordinateByteCount
  )
}
