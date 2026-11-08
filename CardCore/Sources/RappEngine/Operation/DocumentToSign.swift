// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The document a `sign_document` names (RAPP v26.11.8 §9.3): a single
/// document by its name, or a package by its own name and the files it
/// holds.
internal struct DocumentToSign: Equatable, Sendable {
  /// The document's display name; for a package, the package's own name.
  internal let name: String
  /// The files a package holds; nil for a single document.
  internal let containedFiles: ContainedFiles?

  /// The context a PIN prompt shows the holder (§11 item 1).
  internal var context: [String: WireValue] {
    var fields: [String: WireValue] = ["document_name": .text(name)]
    if let containedFiles {
      fields["contained_files"] = .array(containedFiles.names.map(WireValue.text))
    }
    return fields
  }
}
