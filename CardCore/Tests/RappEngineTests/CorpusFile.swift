// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The vendored RAPP v26.10.21 documents the engine is replayed against.
internal enum CorpusFile {
  private static let conformanceName = "rapp-v26.10.21.json"
  private static let operationName = "rapp-operation-v26.10.21.json"
  private static let routingName = "rapp-routing-v26.10.21.json"
  private static let withdrawalName = "rapp-withdrawal-v26.10.21.json"

  /// Test sources sit four directories below the repository root.
  private static let depthBelowRepositoryRoot = 4

  internal static func conformance(filePath: String) throws -> Corpus {
    try JSONDecoder().decode(
      Corpus.self, from: try data(named: conformanceName, filePath: filePath))
  }

  internal static func operation(filePath: String) throws -> OperationCorpus {
    try JSONDecoder().decode(
      OperationCorpus.self, from: try data(named: operationName, filePath: filePath))
  }

  internal static func routing(filePath: String) throws -> RoutingCorpus {
    try JSONDecoder().decode(
      RoutingCorpus.self, from: try data(named: routingName, filePath: filePath))
  }

  internal static func withdrawal(filePath: String) throws -> WithdrawalCorpus {
    try JSONDecoder().decode(
      WithdrawalCorpus.self, from: try data(named: withdrawalName, filePath: filePath))
  }

  private static func repositoryRoot(from filePath: String) -> URL {
    var url = URL(fileURLWithPath: filePath)
    for _ in 0..<depthBelowRepositoryRoot {
      url = url.deletingLastPathComponent()
    }
    return url
  }

  private static func data(named name: String, filePath: String) throws -> Data {
    try Data(
      contentsOf: repositoryRoot(from: filePath)
        .appendingPathComponent("Documentation/rapp-conformance")
        .appendingPathComponent(name))
  }
}
