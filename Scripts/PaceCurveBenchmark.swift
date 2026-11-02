// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A small command-line benchmark for the hot arithmetic used by PACE:
/// one full-width scalar multiplication of the generator on each curve the
/// FINEID cards publish.
///
/// Compile this file in one module with the CardCore sources it uses so
/// internal fixed-width constants remain available:
///
///     swiftc -O -whole-module-optimization \
///       CardCore/Sources/CardCore/Crypto/U384.swift \
///       CardCore/Sources/CardCore/Crypto/MontgomeryDomain.swift \
///       CardCore/Sources/CardCore/Crypto/CurveFieldElement.swift \
///       CardCore/Sources/CardCore/Crypto/CurvePoint.swift \
///       CardCore/Sources/CardCore/Crypto/CurveDomainParameters.swift \
///       CardCore/Sources/CardCore/Crypto/PaceCurve.swift \
///       CardCore/Sources/CardCore/Crypto/JacobianPoint.swift \
///       CardCore/Sources/CardCore/Crypto/BrainpoolP384r1.swift \
///       CardCore/Sources/CardCore/Crypto/NistP384.swift \
///       CardCore/Sources/CardCore/Crypto/NistP256.swift \
///       CardCore/Sources/CardCore/Values/BrainpoolP384r1Values.swift \
///       CardCore/Sources/CardCore/Values/NistP256Values.swift \
///       CardCore/Sources/CardCore/Values/NistP384Values.swift \
///       CardCore/Sources/CardCore/Values/Sec1Values.swift \
///       Scripts/PaceCurveBenchmark.swift \
///       -o /tmp/refineid-pace-curve-benchmark
///
///     /tmp/refineid-pace-curve-benchmark
@main
private enum PaceCurveBenchmark {
  /// Enough samples to show warm performance without making the run slow.
  private static let sampleCount = 9

  /// Unit conversions for a `Duration.Components` value.
  private static let millisecondsPerSecond = 1_000.0
  private static let attosecondsPerMillisecond = 1_000_000_000_000_000.0

  /// The repeated byte forming the benchmark scalars, below every order.
  private static let scalarByte: UInt8 = 90

  /// A fixed scalar as wide as the curve's scalars.
  ///
  /// Every sample then exercises the full loop.
  private static func scalar<Curve: PaceCurve>(_: Curve.Type) -> U384 {
    guard
      let value = U384(
        bigEndianBytes: Data(repeating: scalarByte, count: Curve.coordinateByteCount)
      )
    else {
      fatalError("The fixed-width benchmark scalar could not be constructed")
    }
    return value
  }

  private static func measure<Curve: PaceCurve>(_ curve: Curve.Type, name: String) {
    let scalar = scalar(curve)
    for sample in 0..<sampleCount {
      let start = ContinuousClock.now
      let point = Curve.multiplyGenerator(by: scalar)
      let elapsed = start.duration(to: .now)
      guard let marker = point.encodeUncompressed()?.last else {
        fatalError("A nonzero scalar unexpectedly produced infinity")
      }
      let milliseconds =
        Double(elapsed.components.seconds) * millisecondsPerSecond
        + Double(elapsed.components.attoseconds) / attosecondsPerMillisecond
      print("\(name) \(sample): \(milliseconds) ms [\(marker)]")
    }
  }

  static func main() {
    measure(BrainpoolP384r1.self, name: "brainpoolP384r1")
    measure(NistP384.self, name: "P-384")
    measure(NistP256.self, name: "P-256")
  }
}
