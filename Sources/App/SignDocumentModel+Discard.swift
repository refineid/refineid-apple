// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation

  /// A finished signature stays in memory until it is written or the
  /// holder forgets it.
  extension SignDocumentModel {
    /// Whether `candidate` names the same file as one of `originals`,
    /// through symbolic links and in either letter case.
    nonisolated internal static func isOriginal(_ candidate: URL, among originals: [URL]) -> Bool {
      let candidatePath = Self.resolved(candidate)
      let candidateIdentity = Self.identity(of: candidate)
      return originals.contains { original in
        if let candidateIdentity, let identity = Self.identity(of: original),
          candidateIdentity.isEqual(identity)
        {
          return true
        }
        return Self.resolved(original).caseInsensitiveCompare(candidatePath) == .orderedSame
      }
    }

    /// The path with every symbolic link in its folder resolved.
    nonisolated private static func resolved(_ url: URL) -> String {
      let folder = url.standardizedFileURL.deletingLastPathComponent()
      return folder.resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
    }

    /// The file system's identifier of an existing file.
    nonisolated private static func identity(of url: URL) -> NSObject? {
      (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]))?
        .fileResourceIdentifier as? NSObject
    }

    /// Asks `choose` for a place and writes `finished` there; answers
    /// whether it was written.
    ///
    /// Cancelling discards the signed output. A place
    /// that is one of `originals`, or a write that fails, shows its
    /// failure and asks again. Each request proposes the name last
    /// typed.
    internal func save(
      _ finished: SignedDocument,
      originals: [URL],
      refusal: String,
      choose: DestinationChoice
    ) async -> Bool {
      var typedName: String?
      while true {
        let answer = await choose(finished, typedName)
        typedName = answer.typedName
        guard let destination = answer.destination else { return false }
        guard !Self.isOriginal(destination, among: originals) else {
          await failAndWait(refusal)
          continue
        }
        do {
          try finished.bytes.write(to: destination, options: .atomic)
        } catch {
          await failAndWait(
            DiskFullMessage.message(for: error, otherwise: error.localizedDescription))
          continue
        }
        complete(with: destination)
        return true
      }
    }

    /// Shows `message` as the failure alert and waits until it is
    /// acknowledged or cleared.
    internal func failAndWait(_ message: String) async {
      await withCheckedContinuation { continuation in
        acknowledgement?.resume()
        acknowledgement = continuation
        fail(message: message)
      }
    }

    /// Resumes a signature waiting on its failure alert.
    internal func releaseAcknowledgement() {
      let waiting = acknowledgement
      acknowledgement = nil
      waiting?.resume()
    }
  }

#endif
