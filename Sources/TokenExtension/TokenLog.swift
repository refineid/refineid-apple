// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG
  import CardCore
  import Foundation
  import OSLog
#endif

/// Diagnostic logging for the token extension.
///
/// The extension runs inside ctkd, where no debugger or probe reaches it,
/// so this is the only window into the real createToken/sign invocations.
/// Every line goes to os.Logger AND is appended to a file in the
/// extension's tmp dir, which is pullable over wireless without a USB swap:
///   xcrun devicectl device copy from --device <id> \
///     --domain-type appDataContainer --domain-identifier fi.refineid.ReFineID.token \
///     --source tmp/refineid-token-extension.log --destination /tmp/trace.log
/// No PIN, PUK, full serial, or certificate content is ever logged - only
/// lengths, status words, and control flow (release plan section 4.3).
///
/// Debug and Profile builds only. A shipped build says nothing at all:
/// TestFlight and Release define no `DEBUG`, so every function here is
/// empty. Nothing is written to the system log, no file is created and
/// no keychain item is touched.
///
/// The message is an `@autoclosure` so that a shipped build does not
/// build a line nobody reads. A plain `String` was measured leaving
/// about twenty trace fragments in the optimized binary: an empty
/// inlined function removes the call, but not always the interpolation
/// that produced its argument. The Swift release manager's `inspect-archive`
/// command fails an archive in which any of them reappear.
///
/// One cost, worth knowing before writing a call: a closure formed in a
/// scope that consumes a noncopyable value makes Swift 6.3.3 report a
/// copy of a noncopyable value at the `consume`, and call it a compiler
/// bug. Take what the line needs into a copyable local first -
/// ``TokenSession/signInField(token:dataToSign:algorithm:)``
/// is the one place that has had to.
internal enum TokenLog {
  #if DEBUG
    private static let logger = Logger(subsystem: "fi.refineid.ReFineID", category: "ctk")
    private static let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("refineid-token-extension.log")
  #endif

  @inline(__always)
  internal static func info(_ message: @autoclosure () -> String) {
    #if DEBUG
      // Evaluated once into a local: os.Logger's own interpolation
      // is an escaping autoclosure, and a non-escaping one cannot
      // be called inside it.
      let text = message()
      Self.logger.info("\(text, privacy: .public)")
      Self.append("INFO \(text)")
    #endif
  }

  /// Notice level persists to the on-device log store, so a trace of the
  /// load-bearing control flow (supports/sign/beginAuth) survives long
  /// enough to be collected after a Safari attempt; `info` is memory-only.
  @inline(__always)
  internal static func notice(_ message: @autoclosure () -> String) {
    #if DEBUG
      // Evaluated once into a local: os.Logger's own interpolation
      // is an escaping autoclosure, and a non-escaping one cannot
      // be called inside it.
      let text = message()
      Self.logger.notice("\(text, privacy: .public)")
      Self.append("NOTICE \(text)")
    #endif
  }

  @inline(__always)
  internal static func error(_ message: @autoclosure () -> String) {
    #if DEBUG
      // Evaluated once into a local: os.Logger's own interpolation
      // is an escaping autoclosure, and a non-escaping one cannot
      // be called inside it.
      let text = message()
      Self.logger.error("\(text, privacy: .public)")
      Self.append("ERROR \(text)")
    #endif
  }

  /// A line for the shared trace only, recorded but not written out yet.
  ///
  /// The lines taken inside a live field take this cheap path on purpose.
  /// A contactless signature runs in a field that lasts about two
  /// seconds, and a file write plus a keychain round trip per APDU would
  /// spend that field on narrating itself; ``ExtensionTrace/record(_:)``
  /// only touches memory. They reach the shared item at the next ordinary
  /// log line, which on every path here is the one that ends the
  /// operation.
  @inline(__always)
  internal static func trace(_ message: @autoclosure () -> String) {
    #if DEBUG
      ExtensionTrace.record(message())
    #endif
  }

  /// Writes out everything ``trace(_:)`` has recorded.
  ///
  /// Called where an operation ends without a log line of its own, so a
  /// trace is never left stranded in a process ctkd is about to reap.
  @inline(__always)
  internal static func flush() {
    #if DEBUG
      ExtensionTrace.flush()
    #endif
  }

  #if DEBUG
    /// Appends one timestamped line to the pullable file log, and to the
    /// trace the containing app can read.
    ///
    /// The file above lives in this extension's own container, which no other
    /// process may open, so on iOS 26 - where `log stream --device` is gone
    /// and `log collect` fails - it is unreachable from a cable. Every line
    /// therefore also goes to `ExtensionTrace`, a bounded keychain buffer in
    /// the shared access group, which the app prints on demand. Both carry
    /// the same already-sanitized text.
    private static func append(_ line: String) {
      let stamp = ISO8601DateFormatter().string(from: Date())
      ExtensionTrace.append(line)
      let data = Data("[\(stamp)] \(line)\n".utf8)
      if let handle = try? FileHandle(forWritingTo: Self.fileURL) {
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
      } else {
        try? data.write(to: Self.fileURL, options: .atomic)
      }
    }
  #endif
}
