// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The files a package holds, as the `contained_files` of `sign_document`
/// carry them (RAPP v26.11.8 §9.3).
///
/// They are the names of the data objects as the container holds them, in
/// container order, at least one, each within the name bound and not
/// blank, unique, none under `META-INF/` in any letter case.
///
/// Whether the request they travel in fits one frame is the request's
/// predicate, checked by ``OperationRequest/validate()``.
internal struct ContainedFiles: Equatable, Sendable {
  /// The entries, in container order; never empty.
  internal let names: [String]

  internal init(names: [String]) throws {
    guard !names.isEmpty else { throw CardOperationError.invalidField(field: "contained_files") }
    let reserved = OperationLimit.containerReservedDirectory
    var seen: Set<String> = []
    for name in names {
      try CardOperation.validateDisplayName(name)
      let underReserved = name.prefix(reserved.count).lowercased() == reserved.lowercased()
      guard !underReserved, seen.insert(name).inserted else {
        throw CardOperationError.invalidField(field: "contained_files")
      }
    }
    self.names = names
  }
}
