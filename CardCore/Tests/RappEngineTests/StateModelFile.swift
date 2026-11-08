// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import RappEngine

/// The vendored formal state model the transcription is checked against.
internal enum StateModelFile {
  private static let name = "rapp-state-machine-v26.11.8.yaml"

  /// The document revision this transcription was made from.
  internal static let expectedDocumentVersion = "26.11.8"

  /// Test sources sit four directories below the repository root.
  private static let depthBelowRepositoryRoot = 4

  internal static func read(filePath: String) throws -> ModelReader {
    ModelReader(text: try text(filePath: filePath))
  }

  /// The lifecycle machines of the same document.
  internal static func lifecycle(filePath: String) throws -> LifecycleModel {
    LifecycleModel(text: try text(filePath: filePath))
  }

  private static func text(filePath: String) throws -> String {
    var url = URL(fileURLWithPath: filePath)
    for _ in 0..<depthBelowRepositoryRoot {
      url = url.deletingLastPathComponent()
    }
    let model = url.appendingPathComponent("Documentation/protocol").appendingPathComponent(name)
    return try String(contentsOf: model, encoding: .utf8)
  }
}
