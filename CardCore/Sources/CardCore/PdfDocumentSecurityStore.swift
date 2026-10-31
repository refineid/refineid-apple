// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Reads the document security store a PDF carries (ETSI EN 319 142-1
/// clause 5.4.2).
internal enum PdfDocumentSecurityStore {
  /// The store's certificates, OCSP responses and CRLs, or nothing
  /// when the document carries no readable store.
  internal static func material(in document: Data) -> PdfValidationStore.Material {
    let empty = PdfValidationStore.Material(
      certificates: [], ocspResponses: [], revocationLists: []
    )
    guard
      let index = try? PdfDocumentIndex.parse(document),
      let rootNumber = PdfDocumentIndex.reference(named: "/Root", in: index.trailer),
      let catalog = index.body(of: rootNumber, in: document),
      let store = try? PdfValidationStore.previousStore(
        in: catalog, index: index, document: document
      )
    else {
      return empty
    }
    let bytes = PdfBytes(document)
    func payloads(_ references: [PdfValidationStore.StoreReference]) -> [Data] {
      references.compactMap { reference in
        guard case .direct(let offset) = index.locations[reference.number] else {
          return nil
        }
        return try? PdfStreamObject.parse(in: bytes, at: offset).payload
      }
    }
    return PdfValidationStore.Material(
      certificates: payloads(store.certificates),
      ocspResponses: payloads(store.ocspResponses),
      revocationLists: payloads(store.revocationLists)
    )
  }
}
