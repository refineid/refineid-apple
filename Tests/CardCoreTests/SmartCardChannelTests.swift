// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(CryptoTokenKit)
  import CryptoTokenKit
  import Foundation
  import Testing

  @testable import CardCore

  /// Unit tests for unified ``SmartCardChannel`` session lifecycle, departure polling,
  /// protocol fallback negotiation, APDU timeout handling, and Case-4 signature routing.
  @Suite("SmartCardChannel")
  internal struct SmartCardChannelTests {
    private enum SampleFailure: Error, Equatable {
      case bodyFailed
    }

    /// Minimal ISO 7816-3 direct-convention contact ATR (`TS=3B`, `T0=00`).
    private static let contactATR = WireHex.data("3B00")

    /// Synthetic protected Case-4 maximum-length `PSO:CDS` command (`Le=00`).
    private static let protectedMaximumSignature = WireHex.data(
      "0C2A9E9A0D9701008E08000102030405060700"
    )

    private static let shortTimeoutMilliseconds = 25
    private static let longSessionBudgetSeconds = 10
    private static let departureSessionBudgetSeconds = 30
    private static let promptExitCeilingSeconds = 5
    private static let concurrentEndTasks = 4

    private static var defaultPolicy: SmartCardChannel.WaitPolicy {
      SmartCardChannel.WaitPolicy(
        sessionWait: .seconds(longSessionBudgetSeconds),
        responseWait: .seconds(longSessionBudgetSeconds),
        signatureRoute: .raw
      )
    }

    @Test("OpenSession drives StatefulSmartCardMock and ends at most once")
    internal func openSessionAndEndAreIdempotent() throws {
      let backing = MockSmartCardBacking()
      backing.answerToReset = Self.contactATR
      let channel = SmartCardChannel(backing: backing, policy: Self.defaultPolicy, trace: .silent)

      #expect(channel.readChunkLength == .plain)
      #expect(channel.answerToReset == Self.contactATR)

      let session = try channel.openSession()
      #expect(backing.beginCount == 1)
      #expect(backing.endCount == 0)

      let selectReply = try session.channel.transmit(
        CommandApdu.selectApplication(.fineidApplication).encoded
      )
      #expect(selectReply == WireHex.data("9000"))
      #expect(backing.cardMock.selectCount == 1)

      let unauthenticatedSign = try session.channel.transmit(
        CommandApdu.computeSignatureOverLoadedHash().encoded
      )
      #expect(unauthenticatedSign == WireHex.data("6982"))

      session.end()
      session.end()
      #expect(backing.endCount == 1)
    }

    @Test("withSession ends on throw and SessionWait releases late callbacks")
    internal func withSessionEndsOnThrowAndReleasesAbandonedCallback() throws {
      let backing = MockSmartCardBacking()
      let channel = SmartCardChannel(backing: backing, policy: Self.defaultPolicy, trace: .silent)

      #expect(throws: SampleFailure.bodyFailed) {
        try channel.withSession { _ in
          throw SampleFailure.bodyFailed
        }
      }
      #expect(backing.beginCount == 1)
      #expect(backing.endCount == 1)

      let lateBacking = MockSmartCardBacking()
      let capturedReply = SmartCardChannel.Box<(@Sendable (Bool, (any Error)?) -> Void)?>(nil)
      lateBacking.beginHandler = { _, reply in
        capturedReply.value = reply
      }
      let shortPolicy = SmartCardChannel.WaitPolicy(
        sessionWait: .milliseconds(Self.shortTimeoutMilliseconds),
        responseWait: .milliseconds(Self.shortTimeoutMilliseconds),
        signatureRoute: .raw
      )
      let impatient = SmartCardChannel(backing: lateBacking, policy: shortPolicy, trace: .silent)

      #expect(throws: CardOperationError.sessionUnavailable) {
        try impatient.beginSession()
      }
      #expect(lateBacking.endCount == 0)

      let deliverLate = try #require(capturedReply.value)
      deliverLate(true, nil)
      #expect(lateBacking.endCount == 1)
    }

    @Test("Contact session retries narrower protocol offer on communication error only")
    internal func protocolNegotiationRetriesNarrowerOfferOnCommunicationError() throws {
      let backing = MockSmartCardBacking()
      backing.answerToReset = Self.contactATR
      let communicationFailure = NSError(
        domain: TKErrorDomain,
        code: TKError.Code.communicationError.rawValue
      )
      backing.beginHandler = { offered, reply in
        if offered == .any {
          reply(false, communicationFailure)
        } else {
          reply(true, nil)
        }
      }
      let channel = SmartCardChannel(backing: backing, policy: Self.defaultPolicy, trace: .silent)
      try channel.beginSession()
      #expect(backing.offeredProtocols == [.any, .t0])
      channel.endSession()
      #expect(backing.endCount == 1)

      let nonRetryable = MockSmartCardBacking()
      nonRetryable.answerToReset = Self.contactATR
      let missingObject = NSError(
        domain: TKErrorDomain,
        code: TKError.Code.objectNotFound.rawValue
      )
      nonRetryable.beginHandler = { _, reply in
        reply(false, missingObject)
      }
      let failingChannel = SmartCardChannel(
        backing: nonRetryable,
        policy: Self.defaultPolicy,
        trace: .silent
      )
      do {
        try failingChannel.beginSession()
        Issue.record("Expected non-retryable TKError.objectNotFound failure")
      } catch let caught as NSError {
        #expect(caught.domain == TKErrorDomain)
        #expect(caught.code == TKError.Code.objectNotFound.rawValue)
      }
      #expect(nonRetryable.offeredProtocols == [.any])
    }

    @Test("Session wait exits promptly when card leaves slot before session budget expires")
    internal func beginSessionExitsPromptlyWhenCardLeavesSlot() {
      let backing = MockSmartCardBacking()
      backing.beginHandler = { _, _ in
        // Card leaves the slot while a stalled holder never completes beginSession.
        backing.slotState = .empty
      }
      let policy = SmartCardChannel.WaitPolicy(
        sessionWait: .seconds(Self.departureSessionBudgetSeconds),
        responseWait: .seconds(Self.longSessionBudgetSeconds),
        signatureRoute: .raw
      )
      let channel = SmartCardChannel(backing: backing, policy: policy, trace: .silent)

      let started = ContinuousClock.now
      #expect(throws: CardOperationError.sessionUnavailable) {
        try channel.beginSession()
      }
      let elapsed = started.duration(to: ContinuousClock.now)
      #expect(elapsed < .seconds(Self.promptExitCeilingSeconds))
      #expect(backing.endCount == 0)
    }

    @Test("OpenSession ends on deinit and under concurrent end calls")
    internal func openSessionDeinitAndConcurrentEndRunOnce() async throws {
      let deinitBacking = MockSmartCardBacking()
      do {
        let scoped = SmartCardChannel(
          backing: deinitBacking,
          policy: Self.defaultPolicy,
          trace: .silent
        )
        _ = try scoped.openSession()
        #expect(deinitBacking.beginCount == 1)
      }
      #expect(deinitBacking.endCount == 1)

      let concurrentBacking = MockSmartCardBacking()
      let channel = SmartCardChannel(
        backing: concurrentBacking,
        policy: Self.defaultPolicy,
        trace: .silent
      )
      let session = try channel.openSession()
      await withTaskGroup(of: Void.self) { group in
        for _ in 0..<Self.concurrentEndTasks {
          group.addTask {
            session.end()
          }
        }
      }
      #expect(concurrentBacking.endCount == 1)
    }

    @Test("transmit propagates callback errors, unanswered replies, and DEBUG traces")
    internal func transmitPropagatesFailuresAndDeliversDebugTraces() throws {
      let backing = MockSmartCardBacking()
      let recordedExchanges = SmartCardChannel.Box(0)
      let recordedErrors = SmartCardChannel.Box(0)
      let sink = SmartCardChannel.TraceSink(
        exchange: { _ in recordedExchanges.value += 1 },
        trace: nil,
        error: { _ in recordedErrors.value += 1 }
      )
      let channel = SmartCardChannel(backing: backing, policy: Self.defaultPolicy, trace: sink)
      let command = CommandApdu.selectApplication(.fineidApplication).encoded

      backing.transmitHandler = { _, _, reply in reply(nil, nil) }
      #expect(throws: CardOperationError.exchangeUnanswered) {
        _ = try channel.transmit(command)
      }

      backing.transmitHandler = { _, _, reply in reply(nil, SampleFailure.bodyFailed) }
      #expect(throws: SampleFailure.bodyFailed) {
        _ = try channel.transmit(command)
      }
      #if DEBUG
        #expect(recordedExchanges.value == 2)
        #expect(recordedErrors.value == 1)
      #endif
    }

    @Test("transmit delivers response and throws responseTimedOut when callback stalls")
    internal func transmitDeliversResponseAndTimesOutDeterministically() throws {
      let backing = MockSmartCardBacking()
      let policy = SmartCardChannel.WaitPolicy(
        sessionWait: .milliseconds(Self.shortTimeoutMilliseconds),
        responseWait: .milliseconds(Self.shortTimeoutMilliseconds),
        signatureRoute: .raw
      )
      let channel = SmartCardChannel(backing: backing, policy: policy, trace: .silent)

      #expect(channel.exchangeProgressSnapshot == "operation=none")
      let response = try channel.transmit(CommandApdu.selectApplication(.fineidApplication).encoded)
      #expect(response == WireHex.data("9000"))
      #expect(channel.exchangeProgressSnapshot.contains("ins=A4"))
      #expect(channel.exchangeProgressSnapshot.contains("waiterTimedOut=false"))

      backing.transmitHandler = { _, _, _ in
        // Intentionally never answers to verify the APDU response timeout.
      }
      #expect(throws: SmartCardChannel.TransportError.responseTimedOut) {
        _ = try channel.transmit(CommandApdu.selectApplication(.fineidApplication).encoded)
      }
      #expect(channel.exchangeProgressSnapshot.contains("waiterTimedOut=true"))
    }

    @Test("Protected maximum-response signature obeys structured vs raw SignatureRoute")
    internal func protectedSignatureFollowsConfiguredRoute() throws {
      let structuredBacking = MockSmartCardBacking()
      let structuredPolicy = SmartCardChannel.WaitPolicy(
        sessionWait: .seconds(Self.longSessionBudgetSeconds),
        responseWait: .seconds(Self.longSessionBudgetSeconds),
        signatureRoute: .structured
      )
      let structuredChannel = SmartCardChannel(
        backing: structuredBacking,
        policy: structuredPolicy,
        trace: .silent
      )
      let structuredReply = try structuredChannel.transmit(Self.protectedMaximumSignature)
      #expect(structuredBacking.structuredSendCount == 1)
      #expect(structuredBacking.rawTransmitCount == 0)
      #expect(
        structuredReply == structuredBacking.cardMock.dummySignature + WireHex.data("9000")
      )

      let rawBacking = MockSmartCardBacking()
      let rawChannel = SmartCardChannel(
        backing: rawBacking,
        policy: Self.defaultPolicy,
        trace: .silent
      )
      let rawReply = try rawChannel.transmit(Self.protectedMaximumSignature)
      #expect(rawBacking.rawTransmitCount == 1)
      #expect(rawBacking.structuredSendCount == 0)
      #expect(rawReply == WireHex.data("9000"))
    }
  }
#endif
