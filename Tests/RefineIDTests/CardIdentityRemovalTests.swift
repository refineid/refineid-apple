// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Testing

@testable import RefineID

@Suite("Shared identity cleanup")
@MainActor
internal struct CardIdentityRemovalTests {
  @Test("All cleanup stages complete even when identity reset fails", arguments: [false, true])
  internal func completesSharedCleanup(resetSucceeded: Bool) async {
    var stages: [String] = []
    let outcome = await CardIdentityRemoval.perform(
      reset: {
        stages.append("identity")
        return CardStateReset.Outcome(lines: [], succeeded: resetSucceeded)
      },
      forgetCredentials: { stages.append("credentials") },
      clearPhotos: { stages.append("photos") },
      removeRemoteConfiguration: {
        stages.append("remote-start")
        await Task.yield()
        stages.append("remote-finished")
        return CardIdentityRemoval.ConfigurationRemoval(succeeded: true, failures: [])
      })
    #expect(stages == ["identity", "credentials", "photos", "remote-start", "remote-finished"])
    #expect(outcome.succeeded == resetSucceeded)
  }

  @Test("Namespace deletion failure is reported instead of successful cleanup")
  internal func remoteFailureIsReported() async {
    var completedStages = 0
    let outcome = await CardIdentityRemoval.perform(
      reset: { CardStateReset.Outcome(lines: [], succeeded: true) },
      forgetCredentials: { completedStages += 1 },
      clearPhotos: { completedStages += 1 },
      removeRemoteConfiguration: {
        CardIdentityRemoval.ConfigurationRemoval(
          succeeded: false, failures: ["Cleanup failure: keychain namespace (OSStatus=-50)"])
      })
    #expect(completedStages == 2)
    #expect(!outcome.succeeded)
    #expect(outcome.summary.contains("keychain namespace (OSStatus=-50)"))
  }
}
