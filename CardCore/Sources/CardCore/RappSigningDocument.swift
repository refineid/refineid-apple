// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation

  /// The document a requester asks its custodian to sign (RAPP v26.11.8
  /// §9.3): a single document by its name, or a package by its own name
  /// and the names of the files it holds, in container order.
  public struct RappSigningDocument: Sendable, Equatable {
    /// The document's name; for a package, the package's own name.
    public let name: String
    /// The files a package holds; empty for a single document.
    public let containedFiles: [String]

    /// A document named `name`, holding `containedFiles` when it is a
    /// package.
    public init(name: String, containedFiles: [String]) {
      self.name = name
      self.containedFiles = containedFiles
    }
  }
#endif
