// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The brainpoolP384r1 curve, RFC 5639 section 3.6.
///
/// Standardized domain parameter 16 (BSI TR-03110-3 table 4). The citizen
/// cards run PACE over it (FINEID S4-1 v4.2 section 3.2).
public enum BrainpoolP384r1: PaceCurve {
  /// The parameters of RFC 5639 section 3.6.
  public static let parameters = CurveDomainParameters(
    prime: BrainpoolP384r1Values.prime,
    coefficientA: BrainpoolP384r1Values.coefficientA,
    coefficientB: BrainpoolP384r1Values.coefficientB,
    generatorX: BrainpoolP384r1Values.generatorX,
    generatorY: BrainpoolP384r1Values.generatorY,
    order: BrainpoolP384r1Values.order,
    coordinateByteCount: BrainpoolP384r1Values.coordinateByteCount
  )

  /// The cofactor `h`, which is 1 for this curve.
  public static let cofactor = BrainpoolP384r1Values.cofactor
}
