// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import RappEngine

/// Names a thrown failure the way the conformance corpus names it.
internal enum CorpusFailure {
  internal static func name(_ body: () throws -> Void) -> String? {
    do {
      try body()
      return nil
    } catch let error as WireError {
      return error.description
    } catch {
      return "\(error)"
    }
  }
}
