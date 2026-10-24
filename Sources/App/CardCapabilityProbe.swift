// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && REFINEID_LOCAL_CARD && os(iOS)

  import CardCore
  import Foundation

  /// Asks the card what it can do, and times what it costs to use it.
  ///
  /// Two questions, one hold. EF.CardAccess says which PACE variants and
  /// domain parameters the card supports, which is what decides whether
  /// the fixed suite is the cheapest one available. Then PACE itself is
  /// run and timed, so a suite change has a before to compare against.
  ///
  /// The per-command milliseconds are already in the extension trace --
  /// the app's channel writes there through ``AppTrace`` -- so this adds
  /// only the totals and the reading of the advertised list.
  ///
  /// DEBUG only, and deliberately not on the login path: reading
  /// EF.CardAccess costs a SELECT and a READ BINARY that a login has no
  /// use for.
  internal enum CardCapabilityProbe {
    /// The suite `PaceCommand.securityEnvironment()` fixes, named the
    /// way EF.CardAccess names it, so the report can say whether the
    /// card actually advertises what this build sends.
    private static let runningSuite = "PACE-ECDH-GM-AES-CBC-CMAC-256"

    /// The domain parameter that suite is pinned to.
    private static let runningParameterID = 16

    /// Reads the advertised capabilities and times one PACE run.
    internal static func run() async -> [String] {
      let session: NearFieldCardSession
      do {
        session = try await NearFieldCardSession.open(showing: .cardStatus)
      } catch {
        return ["no field: \(error)"]
      }
      defer { session.end() }
      let sheet = session.meter(.cardStatus)
      let accessNumber = CardCredentialStore.cardAccessNumber()
      let lines = await Self.onCardQueue {
        Self.measure(session: session, accessNumber: accessNumber)
      }
      sheet.finish()
      return lines
    }

    /// The whole measurement, inside the card's exclusive session.
    private static func measure(
      session: NearFieldCardSession,
      accessNumber: CardAccessNumber?
    ) -> [String] {
      do {
        return try session.withCardSession { channel in
          var lines = Self.advertised(channel: channel)
          guard let accessNumber else {
            lines.append("")
            lines.append("pace: not run, no card access number stored")
            return lines
          }
          lines.append("")
          lines.append(contentsOf: Self.paceTiming(channel: channel, accessNumber: accessNumber))
          return lines
        }
      } catch {
        return ["card session failed: \(error)"]
      }
    }

    /// What EF.CardAccess says, and what that means for the fixed suite.
    private static func advertised(channel: some CardChannel) -> [String] {
      let started = ContinuousClock.now
      let operations = CardOperations(channel: channel)
      let infos: [CardAccessFile.SecurityInfo]
      do {
        infos = try operations.readCardAccessInfo()
      } catch {
        return ["EF.CardAccess unreadable: \(error)"]
      }
      let elapsed = TraceTiming.milliseconds(started.duration(to: ContinuousClock.now))
      guard !infos.isEmpty else {
        return ["EF.CardAccess: no entries parsed (read in \(elapsed) ms)"]
      }
      var lines = ["EF.CardAccess (\(infos.count) entries, read in \(elapsed) ms)"]
      lines += infos.map { "  " + $0.summary }
      lines.append("")
      lines += Self.verdict(infos)
      return lines
    }

    /// Whether anything cheaper than the running suite is on offer.
    ///
    /// This is the entire reason the file is read, so it is stated
    /// rather than left for a reader to work out from the list.
    private static func verdict(_ infos: [CardAccessFile.SecurityInfo]) -> [String] {
      let pace = infos.filter(\.isPace)
      guard !pace.isEmpty else {
        return ["verdict: no PACE entry advertised; this build's suite is unconfirmed"]
      }
      var lines: [String] = []
      let advertisesRunning = pace.contains { info in
        info.protocolName == Self.runningSuite && info.parameterID == Self.runningParameterID
      }
      lines.append(
        advertisesRunning
          ? "verdict: the running suite is advertised"
          : "verdict: the running suite is NOT advertised; it works anyway")
      let integrated = pace.filter(\.usesIntegratedMapping)
      lines.append(
        integrated.isEmpty
          ? "verdict: no integrated mapping; the mapping DH is unavoidable"
          : "verdict: integrated mapping IS offered -- "
            + integrated.map { $0.protocolName ?? "" }.joined(separator: ", "))
      // A smaller parameter id is a smaller field; the card's scalar
      // multiplication is what the login spends its time on.
      let smaller = pace.compactMap(\.parameterID).filter { $0 < Self.runningParameterID }
      lines.append(
        smaller.isEmpty
          ? "verdict: no smaller domain parameter offered"
          : "verdict: smaller domain parameters offered -- "
            + smaller.map(String.init).joined(separator: ", "))
      return lines
    }

    /// One PACE run, timed end to end.
    private static func paceTiming(
      channel: some CardChannel,
      accessNumber: CardAccessNumber
    ) -> [String] {
      // PACE runs from the main file, and the read above left it
      // current, so the handshake starts where it must.
      let started = ContinuousClock.now
      do {
        _ = try PaceEstablishment(channel: channel).establish(with: accessNumber)
      } catch {
        return ["pace: failed after \(Self.since(started)) ms: \(error)"]
      }
      return [
        "pace: \(Self.runningSuite) completed in \(Self.since(started)) ms",
        "pace: per-command timings are in the extension trace above",
      ]
    }

    /// Milliseconds since `instant`, in the trace's own format.
    private static func since(_ instant: ContinuousClock.Instant) -> String {
      TraceTiming.milliseconds(instant.duration(to: ContinuousClock.now))
    }

    /// Runs one blocking card exchange off the cooperative pool.
    private static func onCardQueue(
      _ body: @escaping @Sendable () -> [String]
    ) async -> [String] {
      await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          continuation.resume(returning: body())
        }
      }
    }
  }

#endif
