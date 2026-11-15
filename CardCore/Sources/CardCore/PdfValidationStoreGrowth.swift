// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Whether a revision only added to a document security store.
///
/// Long-term validation appends the certificates, OCSP responses and
/// CRLs a validator needs, and a revision may do that after a
/// signature. A store that loses an entry, or rewrites one, takes away
/// evidence instead, so its category arrays may grow and its `/VRI`
/// entries may be added, but nothing already there may change or go
/// (ETSI EN 319 142-1 clause 5.4).
internal enum PdfValidationStoreGrowth {
  /// The store's arrays of object references.
  private static let arrayKeys: Set<String> = ["Certs", "OCSPs", "CRLs"]

  /// The store keys a later revision may touch at all.
  private static let storeKeys: Set<String> = ["Certs", "OCSPs", "CRLs", "VRI"]

  /// Whether the store `body` keeps everything `previous` held.
  internal static func growsOnly(from previous: String, to body: String) -> Bool {
    guard
      let before = try? PdfValidationStore.DictionarySyntax(PdfTypeEntry.dictionary(of: previous)),
      let after = try? PdfValidationStore.DictionarySyntax(
        PdfTypeEntry.dictionary(of: body))
    else {
      return false
    }
    guard changedKeys(from: before, to: after).isSubset(of: storeKeys) else { return false }
    for key in arrayKeys {
      guard arrayKeepsEverything(key, from: before, to: after) else { return false }
    }
    return storeEntriesGrow(from: before, to: after)
  }

  /// Whether one category array still names every object it named.
  private static func arrayKeepsEverything(
    _ key: String,
    from before: PdfValidationStore.DictionarySyntax,
    to after: PdfValidationStore.DictionarySyntax
  ) -> Bool {
    let kept = PdfObjectReferences.references(in: value(of: key, in: before))
    let grown = PdfObjectReferences.references(in: value(of: key, in: after))
    return Set(kept).isSubset(of: Set(grown))
  }

  /// Whether every `/VRI` entry the store had is still there, unchanged,
  /// so new ones may only be added.
  private static func storeEntriesGrow(
    from before: PdfValidationStore.DictionarySyntax,
    to after: PdfValidationStore.DictionarySyntax
  ) -> Bool {
    let kept = value(of: "VRI", in: before)
    let grown = value(of: "VRI", in: after)
    if kept == grown || kept.isEmpty { return true }
    guard
      let keptDictionary = try? PdfValidationStore.DictionarySyntax(kept),
      let grownDictionary = try? PdfValidationStore.DictionarySyntax(grown)
    else {
      return false
    }
    return keptDictionary.entries.allSatisfy { entry in
      grownDictionary.entry(named: entry.name)
        .map { grownDictionary.value(of: $0) } == keptDictionary.value(of: entry)
    }
  }

  /// An entry's value, empty when the dictionary does not have it.
  private static func value(
    of key: String,
    in dictionary: PdfValidationStore.DictionarySyntax
  ) -> String {
    guard let entry = dictionary.entry(named: key) else { return "" }
    return dictionary.value(of: entry)
  }

  /// The entry names whose value differs between two dictionaries.
  private static func changedKeys(
    from before: PdfValidationStore.DictionarySyntax,
    to after: PdfValidationStore.DictionarySyntax
  ) -> Set<String> {
    let names = Set(before.entries.map(\.name)).union(after.entries.map(\.name))
    return names.filter { name in
      before.entry(named: name).map { before.value(of: $0) }
        != after.entry(named: name).map { after.value(of: $0) }
    }
  }
}
