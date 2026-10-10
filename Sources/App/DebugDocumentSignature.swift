// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import CardCore
  import Foundation

  /// Drives one archival signature from the command line, so the whole
  /// path can be exercised against a real card and real authorities
  /// without a hand on the window.
  ///
  /// PIN2 comes from the environment rather than the command line: an
  /// argument is visible in `ps` to every process on the machine, and
  /// this mode exists precisely to be run while other things are
  /// watching. It is never stored and never echoed - only its length,
  /// which is what catches a shell that ate a leading zero.
  ///
  /// DEBUG ONLY, like every mode beside it.
  internal enum DebugDocumentSignature {
    /// Carries one outcome out of the task that produced it.
    private final class OutcomeBox: @unchecked Sendable {
      /// What happened, once the task has recorded it.
      private(set) var report = DebugModeReport(lines: [], succeeded: false)

      /// Records the outcome; called once, before the semaphore is
      /// signalled, so the read that follows sees it.
      func record(line: String, succeeded: Bool) {
        report = DebugModeReport(lines: [line], succeeded: succeeded)
      }
    }
    /// The environment variable carrying PIN2 for this run.
    private static let pinVariable = "REFINEID_PIN2"

    /// Signs the PDF at `path` and reports each step.
    internal static func report(path: String?) -> DebugModeReport {
      guard let path else {
        return DebugModeReport(
          lines: ["--sign-document: expected a PDF path after the flag"],
          succeeded: false
        )
      }
      guard
        let pin2 = ProcessInfo.processInfo.environment[Self.pinVariable],
        !pin2.isEmpty
      else {
        return DebugModeReport(
          lines: ["--sign-document: set \(Self.pinVariable) to the card's PIN2"],
          succeeded: false
        )
      }
      let resolvedPath =
        path.hasPrefix("~/")
        ? NSHomeDirectory() + path.dropFirst()
        : path
      let source = URL(fileURLWithPath: resolvedPath)
      guard let document = try? Data(contentsOf: source) else {
        return DebugModeReport(
          lines: ["--sign-document: cannot read \(source.lastPathComponent)"],
          succeeded: false
        )
      }
      var lines = [
        "--sign-document: \(source.lastPathComponent), \(document.count) bytes",
        "--sign-document: credential provided via \(Self.pinVariable)",
      ]
      let outcome = Self.signed(document, pin2: pin2, source: source)
      lines.append(contentsOf: outcome.lines)
      return DebugModeReport(lines: lines, succeeded: outcome.succeeded)
    }

    /// Runs the signature synchronously and names what happened.
    ///
    /// A launch mode has no run loop to await on, so the async work is
    /// started and waited for on a semaphore - the same shape the other
    /// card-driving modes use.
    private static func signed(
      _ document: Data,
      pin2: String,
      source: URL
    ) -> DebugModeReport {
      let box = OutcomeBox()
      let semaphore = DispatchSemaphore(value: 0)
      Task {
        let started = ContinuousClock.now
        do {
          let product = try await DocumentSigner.sign(
            document,
            named: source.lastPathComponent,
            reason: nil,
            location: nil,
            access: DocumentSigner.SigningAccess(
              pin2: pin2,
              transport: .reader,
              cardAccessNumber: nil
            )
          )
          let destination = SignDocumentModel.destination(
            for: source, at: Date(), format: .pades
          )
          try product.bytes.write(to: destination, options: .atomic)
          box.record(
            line: "--sign-document: wrote \(destination.lastPathComponent), "
              + "\(product.bytes.count) bytes in "
              + TraceTiming.milliseconds(started.duration(to: .now)) + " ms",
            succeeded: true
          )
        } catch {
          box.record(
            line: "--sign-document: failed: \(error)", succeeded: false
          )
        }
        semaphore.signal()
      }
      semaphore.wait()
      return box.report
    }
  }

#endif
