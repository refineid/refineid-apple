// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The vendored CPace KC2 cross-implementation vectors.
internal struct CpaceKc2VectorFile: Decodable {
  private static let fileName = "rapp-cpace-kc2-v26.10.1.json"
  /// Test sources sit four directories below the repository root.
  private static let depthBelowRepositoryRoot = 4

  internal let format: String
  internal let vectors: [CpaceKc2Vector]

  internal static func load(filePath: String) throws -> Self {
    var url = URL(fileURLWithPath: filePath)
    for _ in 0..<depthBelowRepositoryRoot {
      url = url.deletingLastPathComponent()
    }
    let data = try Data(
      contentsOf: url.appendingPathComponent("Documentation/rapp-conformance")
        .appendingPathComponent(fileName))
    return try JSONDecoder().decode(Self.self, from: data)
  }
}
