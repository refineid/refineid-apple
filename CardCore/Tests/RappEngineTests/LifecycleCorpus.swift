// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The vendored lifecycle scenarios (RAPP v26.11.2 §4.7): each walks one
/// machine from a start state through events, naming the state and the
/// ordered actions after each.
internal struct LifecycleCorpus: Decodable {
  private enum CodingKeys: String, CodingKey {
    case format = "format"
    case protocolDocumentVersion = "protocol_document_version"
    case scenarios = "scenarios"
  }

  private static let fileName = "rapp-lifecycle-v26.11.2.json"
  private static let depthBelowRepositoryRoot = 4

  internal let format: String
  internal let protocolDocumentVersion: String
  internal let scenarios: [LifecycleScenario]

  internal static func read(filePath: String) throws -> Self {
    var url = URL(fileURLWithPath: filePath)
    for _ in 0..<depthBelowRepositoryRoot {
      url = url.deletingLastPathComponent()
    }
    return try JSONDecoder().decode(
      Self.self,
      from: try Data(
        contentsOf: url.appendingPathComponent("Documentation/rapp-conformance")
          .appendingPathComponent(fileName)))
  }
}
