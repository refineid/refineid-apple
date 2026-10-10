// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

extension DocumentSigner {
  /// The paired phone's qualified signature certificate, read once per
  /// pairing and shared by every signature that needs it.
  ///
  /// A read already under way is joined rather than repeated, so a
  /// document chosen before Sign is pressed has its certificate ready
  /// by the time the phone is asked to sign.
  internal actor RemoteCertificateStore {
    private var pairID: Data?
    private var read: Task<Data, Error>?

    /// The certificate for `pairID`, reading it with `fetch` when none
    /// is held or under way.
    internal func certificate(
      for pairID: Data?,
      fetch: @escaping @Sendable () throws -> Data
    ) async throws -> Data {
      if pairID != self.pairID {
        self.pairID = pairID
        read = nil
      }
      let current: Task<Data, Error>
      if let read {
        current = read
      } else {
        current = Task.detached(priority: .userInitiated) { try fetch() }
        read = current
      }
      do {
        return try await current.value
      } catch {
        if read == current { read = nil }
        throw error
      }
    }

    /// Forgets the held certificate, as when the phone signed with a
    /// different one.
    internal func forget() {
      read = nil
    }
  }

  /// The process-wide certificate held for the selected pairing.
  internal static let remoteCertificates = RemoteCertificateStore()

  /// Reads the paired phone's signature certificate ahead of a
  /// signature, when the phone is the one that will sign.
  @MainActor
  internal static func prepareRemoteSigning() {
    guard Self.usesRappSigning else { return }
    Task.detached(priority: .utility) {
      _ = try? await Self.remoteSignatureCertificate()
    }
  }

  /// The paired phone's signature certificate, read once per pairing.
  internal static func remoteSignatureCertificate() async throws -> Data {
    let pairID = try? RappDeviceVault().selectedPairID()
    let displayName = ProcessInfo.processInfo.hostName
    return try await Self.remoteCertificates.certificate(for: pairID) {
      try Self.fetchRemoteSignatureCertificate(displayName: displayName)
    }
  }
}
