// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The vendored RAPP v26.10.1 §5.3 SAR vectors.
internal struct BleSarVectorFile: Decodable {
  internal struct CapacityVector: Decodable {
    internal let negotiatedAttMtu: Int
    internal let platformValueLimit: Int?
    internal let capacity: Int?
    internal let error: String?
  }

  internal struct SegmentationVector: Decodable {
    internal let name: String
    internal let capacity: Int
    internal let messageHex: String
    internal let fragmentsHex: [String]
  }

  internal struct TimedFragment: Decodable {
    internal let hex: String
    internal let atMs: UInt64
  }

  internal struct ReceiveVector: Decodable {
    internal let name: String
    internal let capacity: Int
    internal let fragments: [TimedFragment]
    internal let messagesHex: [String]
    internal let error: String?
    internal let atFragment: Int?
  }

  private static let fileName = "rapp-ble-sar-v26.10.1.json"
  /// Test sources sit four directories below the repository root.
  private static let depthBelowRepositoryRoot = 4

  internal let format: String
  internal let protocolDocumentVersion: String
  internal let headerSize: Int
  internal let reassemblyTimeoutMs: UInt64
  internal let capacity: [CapacityVector]
  internal let segmentation: [SegmentationVector]
  internal let receive: [ReceiveVector]

  internal static func load(filePath: String) throws -> Self {
    var url = URL(fileURLWithPath: filePath)
    for _ in 0..<depthBelowRepositoryRoot {
      url = url.deletingLastPathComponent()
    }
    let data = try Data(
      contentsOf: url.appendingPathComponent("Documentation/rapp-conformance")
        .appendingPathComponent(fileName))
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(Self.self, from: data)
  }
}
