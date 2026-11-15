// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// A change a revision made after a signature, which that signature did
/// not allow.
///
/// A signature covers the revision its `/ByteRange` ends, and anyone may
/// append revisions after it, so the verdict has to say what those later
/// revisions touched. An empty list means the file the verifier read is
/// the file the signer saw, plus what signing and long-term validation
/// may add (ISO 32000-1 clause 12.8.2.2; ETSI EN 319 142-1 clause 5.4).
public enum SignedContentChange: Equatable, Hashable, Sendable {
  /// The catalog, the interactive form or the trailer changed in a key
  /// no later revision may touch.
  case documentStructure

  /// An object the rules do not name was added, redefined or removed,
  /// or a stream's bytes were rewritten under the same dictionary.
  case object(Int)

  /// A page, or something a page draws, changed in a way that alters
  /// what is rendered: a page object beyond its `/Annots`, a page tree
  /// node, a content or resource object.
  case pageContent
}
