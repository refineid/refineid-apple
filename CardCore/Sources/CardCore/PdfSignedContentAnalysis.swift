// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What the revisions after a signed one change in a PDF.
///
/// The signed revision is indexed on its own and compared with the
/// newest view of the document, object by object, number by number. An
/// object whose body is the same in both views, at the same generation,
/// is untouched. Every other change or addition must be authorized by
/// PAdES / ISO 32000-1 incremental-signing and LTV rules; anything else
/// is reported as a change after signing.
internal enum PdfSignedContentAnalysis {
  /// Cryptographic and structural facts of one signature dictionary in
  /// the document, used to authorize post-signature fields and widgets.
  internal struct PostSignatureCandidate: Sendable {
    /// The indirect object's number.
    internal let objectNumber: Int

    /// Where the signature dictionary sits in the file.
    internal let location: PdfDocumentIndex.ObjectLocation

    /// The byte length of the revision this signature ends.
    internal let revisionEnd: Int

    /// Whether `/SubFilter` is `ETSI.RFC3161` (`DocTimeStamp`).
    internal let isTimestamp: Bool

    /// Whether CMS digest and signature verification succeeded.
    internal let isCryptographicallyVerified: Bool
  }

  /// Both views of the document and their structural object numbers.
  internal struct Context {
    /// The newest view.
    internal let newest: PdfDocumentIndex

    /// The full document bytes.
    internal let document: Data

    /// The view the signature covers.
    internal let signed: PdfDocumentIndex

    /// The signed revision's bytes.
    internal let signedDocument: Data

    /// The newest catalog's object number.
    internal let catalogNumber: Int?

    /// The signed revision's interactive form object number.
    internal let signedFormNumber: Int?

    /// The newest interactive form's object number.
    internal let formNumber: Int?

    /// Indirect `/Fields` array object number in the signed revision.
    internal let signedIndirectFieldsNumber: Int?

    /// Map from indirect `/Annots` array object number in the signed
    /// revision to its owning `/Page` object numbers.
    internal let signedIndirectPageAnnots: [Int: [Int]]

    /// Whether the signed revision sets no-changes `DocMDP` permission.
    internal let hasNoChangesDocMdp: Bool

    /// Eligible post-signature dictionaries keyed by object number.
    internal let postSignatures: [Int: PostSignatureCandidate]

    /// An object's body in the newest view.
    internal func body(of number: Int) -> String? {
      newest.comparisonBody(of: number, in: document)
    }

    /// An object's body in the signed view.
    internal func signedBody(of number: Int) -> String? {
      signed.comparisonBody(of: number, in: signedDocument)
    }
  }

  /// Mutable binding and reachability state accumulated across one
  /// revision comparison.
  internal struct VerificationState {
    /// Post-signature object number -> widget object number.
    internal var widgetBySignature: [Int: Int] = [:]

    /// Post-signature object number -> `/FT /Sig` field object number.
    internal var fieldBySignature: [Int: Int] = [:]

    /// Newly added indirect object numbers authorized so far.
    internal var allowedAddedObjects: Set<Int>
  }

  /// The entry names that differ between two dictionaries, and whether
  /// both could be read at all.
  internal struct EntryDifferences {
    /// The names whose value is not the same in both.
    internal let names: Set<String>

    /// Whether both dictionaries could be parsed.
    internal let isReadable: Bool
  }

  /// One rewritten indirect object's before/after bodies and dictionary
  /// differences.
  internal struct ObjectComparison {
    /// The indirect object's number.
    internal let number: Int

    /// Its body in the signed revision.
    internal let previous: String

    /// Its body in the newest revision.
    internal let body: String

    /// Top-level dictionary differences between `previous` and `body`.
    internal let differences: EntryDifferences
  }

  /// What the rules say about one rewritten object.
  internal enum Verdict {
    /// The changes the object makes.
    case changes(Set<SignedContentChange>)

    /// No rule names the object, so what it is decides.
    case unnamed
  }

  /// Order base so structure and page changes sort before numbered
  /// objects.
  private static let objectOrderBase = 2

  /// Order placing structure changes before page changes.
  private static let pageOrder = 1

  /// Every change a revision after `signedEnd` made, discovering
  /// post-signature candidates from `document`.
  internal static func changes(
    document: Data,
    signedEnd: Int
  ) -> [SignedContentChange] {
    guard signedEnd > 0, signedEnd < document.count else { return [] }
    return Self.changes(
      document: document,
      signedEnd: signedEnd,
      candidates: Self.discoverCandidates(in: document)
    )
  }

  /// Every change a revision after `signedEnd` made, using precomputed
  /// signature candidates.
  internal static func changes(
    document: Data,
    signedEnd: Int,
    candidates: [PostSignatureCandidate]
  ) -> [SignedContentChange] {
    guard signedEnd > 0, signedEnd < document.count else { return [] }
    guard
      let context = Self.makeContext(
        document: document, signedEnd: signedEnd, candidates: candidates
      )
    else {
      return [.documentStructure]
    }
    var state = VerificationState(
      allowedAddedObjects: Self.initialAllowedAddedObjects(in: context)
    )
    var foundChanges = Self.existingObjectChanges(in: context, state: &state)
    for number in context.newest.locations.keys.sorted()
    where context.signed.locations[number] == nil {
      guard context.body(of: number) != nil,
        state.allowedAddedObjects.contains(number)
      else {
        foundChanges.insert(.object(number))
        continue
      }
    }
    return foundChanges.sorted { lhs, rhs in Self.order(lhs) < Self.order(rhs) }
  }

  /// Discovers signature candidates directly from `document`.
  internal static func discoverCandidates(
    in document: Data
  ) -> [PostSignatureCandidate] {
    guard
      let located = try? PdfSignatureReader.locatedSignatures(
        in: document,
        maximumByteCount: PdfValues.maximumVerifiedDocumentByteCount
      )
    else {
      return []
    }
    return located.compactMap { item in
      guard item.signature.endsRevision else { return nil }
      let isTimestamp = item.signature.subFilter == .rfc3161
      let verified: Bool
      if let profile = DocumentVerification.profile(
        ofSubFilter: item.signature.subFilter
      ) {
        let outcome = CmsSignerVerification.verify(
          cms: item.signature.cms,
          signedOctets: item.signature.signedSpans.signedOctets,
          profile: profile
        )
        verified =
          outcome?.documentIntact == true && outcome?.signatureValid == true
      } else {
        verified = false
      }
      return PostSignatureCandidate(
        objectNumber: item.objectNumber,
        location: item.location,
        revisionEnd: item.signature.signedSpans.document.count,
        isTimestamp: isTimestamp,
        isCryptographicallyVerified: verified
      )
    }
  }

  /// A stable order, so a report reads the same way twice.
  private static func order(_ change: SignedContentChange) -> Int {
    switch change {
    case .documentStructure:
      return 0
    case .pageContent:
      return Self.pageOrder
    case .object(let number):
      let (sum, overflow) = Self.objectOrderBase.addingReportingOverflow(number)
      return overflow ? Int.max : sum
    }
  }
}
