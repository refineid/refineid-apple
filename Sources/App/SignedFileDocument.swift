// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import SwiftUI
  import UniformTypeIdentifiers

  /// The signed bytes handed to the file exporter.
  internal struct SignedFileDocument: FileDocument {
    internal static var readableContentTypes: [UTType] { [.data] }
    /// The signed bytes.
    internal let data: Data

    internal init(data: Data) { self.data = data }

    internal init(configuration: ReadConfiguration) {
      data = configuration.file.regularFileContents ?? Data()
    }

    internal func fileWrapper(
      configuration _: WriteConfiguration
    ) -> FileWrapper {
      FileWrapper(regularFileWithContents: data)
    }
  }

#endif
