// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && (os(iOS) || os(macOS))

  import CardCore
  import CryptoKit
  import Foundation

  /// Asks the paired phone for one browser-authentication signature.
  ///
  /// The same request CryptoTokenKit makes when a website asks for the
  /// card, run from the app instead of the token extension: the extension
  /// has no console, so a failure there is a number and nothing else,
  /// while this reports which step refused and how long it took.
  ///
  /// DEBUG only. The digest is this device's own bytes, never a page's.
  internal enum DebugRemoteSignProbe {
    // MARK: Static Properties

    /// What a second is, where the elapsed line wants milliseconds.
    private static let millisecondsPerSecond = 1_000

    /// A digest of the size the algorithm expects, from local bytes.
    private static var digest: Data {
      Data(SHA384.hash(data: Data("refineid remote sign probe".utf8)))
    }

    // MARK: Static Functions

    /// Runs one signature over the relay and reports what came back.
    internal static func report() -> DebugModeReport {
      var lines = ["remote-sign: asking the paired device"]
      let started = Date()
      do {
        #if os(macOS)
          let displayContext = "macOS CryptoTokenKit"
        #else
          let displayContext = "iOS CryptoTokenKit"
        #endif
        let response = try RappPersistentRequesterClient().perform(
          .browserAuthentication(
            displayContext: displayContext,
            keyProfile: .ecdsaP384,
            algorithm: .ecdsaSHA384,
            digest: digest
          )
        )
        guard case .signature(let signature) = response else {
          lines.append("FAIL: answered something other than a signature")
          return DebugModeReport(lines: lines, succeeded: false)
        }
        lines.append("signature: \(signature.count) bytes")
        lines.append(elapsedLine(since: started))
        return DebugModeReport(lines: lines, succeeded: !signature.isEmpty)
      } catch {
        lines.append("FAIL: \(String(describing: error))")
        lines.append(elapsedLine(since: started))
        return DebugModeReport(lines: lines, succeeded: false)
      }
    }

    /// How long the whole request took, in milliseconds.
    private static func elapsedLine(since started: Date) -> String {
      let elapsed = Date().timeIntervalSince(started) * Double(millisecondsPerSecond)
      return "elapsed: \(Int(elapsed))ms"
    }
  }

#endif
