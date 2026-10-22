// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD && REFINEID_STREAM_TRANSPORT
  import CardCore
  import Foundation
  import os

  /// Takes the operations the RAPP token extension hands over and carries
  /// them on the session this app holds with the phone (CC-71).
  ///
  /// The port lives on a thread of its own: a request blocks that thread
  /// until the main actor has the answer, and never the main thread. Only
  /// processes of the app group can reach it (``RappHeldSessionHandoff``).
  internal enum HeldSessionHandoffPort {
    /// Where the port thread waits for the main actor's answer.
    private final class Answering: Sendable {
      private let answer = OSAllocatedUnfairLock(
        initialState: RappHeldSessionHandoff.Answer.failed(.transport))
      private let done = DispatchSemaphore(value: 0)

      func set(_ value: RappHeldSessionHandoff.Answer) {
        answer.withLock { $0 = value }
        done.signal()
      }

      func wait() -> RappHeldSessionHandoff.Answer {
        done.wait()
        return answer.withLock { $0 }
      }
    }

    /// The thread's name, for a debugger.
    private static let threadName = "fi.refineid.rapp-held-session"

    /// The run loop source's order among the thread's sources; it is the
    /// only one.
    private static let sourceOrder: CFIndex = 0

    /// Answers one request on the port's thread.
    private static let answer: CFMessagePortCallBack = { _, messageID, data, _ in
      guard messageID == RappHeldSessionHandoff.requestMessageID, let data,
        let request = RappHeldSessionHandoff.Request(encoded: data as Data)
      else {
        #if DEBUG
          DevErrorLog.report("handoff request not understood", source: .app)
        #endif
        return nil
      }
      let answering = Answering()
      Task { @MainActor in
        answering.set(await PersistentTokenRegistry.shared.carry(request))
      }
      guard let encoded = answering.wait().encoded() else { return nil }
      return Unmanaged.passRetained(encoded as CFData)
    }

    /// Opens the port on its own thread.
    internal static func start() {
      let thread = Thread { serve() }
      thread.name = threadName
      thread.start()
    }

    private static func serve() {
      guard
        let port = CFMessagePortCreateLocal(
          nil, RappHeldSessionHandoff.portName as CFString, answer, nil, nil),
        let source = CFMessagePortCreateRunLoopSource(nil, port, sourceOrder)
      else {
        #if DEBUG
          DevErrorLog.report("handoff port not opened", source: .app)
        #endif
        return
      }
      CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
      CFRunLoopRun()
    }
  }
#endif
