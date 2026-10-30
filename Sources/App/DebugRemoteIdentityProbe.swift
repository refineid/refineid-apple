// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && (os(iOS) || os(macOS))

  import CardCore
  import CryptoTokenKit
  import Foundation

  /// Asks the paired device for its authentication certificate.
  ///
  /// The peer answers from the prime it read while setting its own identity
  /// up, so no card is presented to anything and the run needs nobody
  /// present. What it exercises is the whole relay between two devices:
  /// the stored pairing, the session over it, one request and one answer.
  internal enum DebugRemoteIdentityProbe {
    /// What a second is, where the elapsed line wants milliseconds.
    private static let millisecondsPerSecond = 1_000

    /// Runs the probe and reports what came back.
    internal static func report() -> DebugModeReport {
      var lines: [String] = []
      lines.append("relay: session machinery")

      let started = Date()
      do {
        let response = try RappPersistentRequesterClient().perform(.readAuthenticationCertificate)
        guard case .authenticationCertificate(let der) = response else {
          lines.append("FAIL: answered something other than a certificate")
          return DebugModeReport(lines: lines, succeeded: false)
        }
        lines.append("certificate: \(der.count) bytes")
        lines.append(Self.holderLine(der))
        lines.append(Self.elapsedLine(since: started))
        lines.append(contentsOf: Self.publishLines(der))
        return DebugModeReport(
          lines: lines,
          succeeded: !der.isEmpty && Self.publishedTokenCount() > 0)
      } catch {
        lines.append("FAIL: \(String(describing: error))")
        lines.append(Self.elapsedLine(since: started))
        return DebugModeReport(lines: lines, succeeded: false)
      }
    }

    /// Publishes the answered certificate and says whether the system took
    /// it.
    ///
    /// This is the step a browser depends on: an identity it is never
    /// offered is one the holder cannot use, however well the relay worked.
    private static func publishLines(_ der: Data) -> [String] {
      let before = publishedTokenCount()
      if Thread.isMainThread {
        MainActor.assumeIsolated {
          _ = PersistentTokenRegistry.publish(der)
        }
      } else {
        DispatchQueue.main.sync {
          MainActor.assumeIsolated {
            _ = PersistentTokenRegistry.publish(der)
          }
        }
      }
      let after = publishedTokenCount()
      return [
        "token configurations: \(before) before, \(after) after",
        after > 0 ? "published: yes" : "published: no",
      ]
    }

    /// How many identities this driver currently offers.
    private static func publishedTokenCount() -> Int {
      let configurations = TKTokenDriver.Configuration.driverConfigurations
      return configurations[PersistentTokenIdentity.classID]?
        .tokenConfigurations.count ?? 0
    }

    /// Whether the answer parses as a certificate, without naming anyone.
    private static func holderLine(_ der: Data) -> String {
      guard let facts = CertificateFacts(der: der) else {
        return "certificate: does not parse"
      }
      let named = DistinguishedName.personalName(inName: facts.subjectName) != nil
      return "certificate: parses, subject names a person: \(named)"
    }

    private static func elapsedLine(since started: Date) -> String {
      let milliseconds = Int(Date().timeIntervalSince(started) * Double(millisecondsPerSecond))
      return "elapsed: \(milliseconds)ms"
    }
  }

#endif
