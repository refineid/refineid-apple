// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// Settings probes: one timestamp exchange with one authority, without retry.
extension TimestampClient {
  /// The imprint source a probe stamps.
  ///
  /// A genuine SHA-384 digest, the size the request demands. The
  /// nonce makes every probe unique; the imprint itself carries no
  /// holder data.
  private static let probeImprintSource = "RefineID timestamp probe"

  /// The probe verdict for a transport error.
  ///
  /// A device without a usable connection reports that instead of
  /// blaming the authority; anything else says the authority did
  /// not answer.
  internal static func probeFailure(from error: Error) -> Failure {
    if SigningNetwork.isOffline(error) {
      return .noNetworkConnection
    }
    return .authorityDidNotAnswer("\(error)")
  }

  /// One timestamp exchange with one authority, without retry.
  ///
  /// For the settings Test action: a single attempt against the typed
  /// address - not the effective authority - that fails fast instead
  /// of retrying behind a button. Anything but a verified token is a
  /// `Failure`, the same verdict signing would reach.
  internal static func probe(_ authority: String) async throws {
    do {
      let digest = Data(
        SHA384.hash(data: Data(Self.probeImprintSource.utf8))
      )
      _ = try await Self.token(over: digest, from: authority)
    } catch is CancellationError {
      throw CancellationError()
    } catch let failure as Failure {
      throw failure
    } catch {
      throw Self.probeFailure(from: error)
    }
  }
}
