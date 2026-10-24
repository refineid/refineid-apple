// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Testing

@testable import CardCore

/// Test isolation is selected by whole launch arguments and the runner's
/// environment key only, never by anything that merely resembles them.
internal struct TestCredentialEnvironmentTests {
  private static let executable = "/Applications/RefineID.app/Contents/MacOS/RefineID"
  private static let runnerKey = "XCTestConfigurationFilePath"
  private static let runnerValue = "runner.xctestconfiguration"

  @Test(
    "A whole selecting argument selects test isolation",
    arguments: ["--ui-test", "--virtual-card"])
  internal func wholeArgumentSelects(argument: String) {
    #expect(
      TestCredentialEnvironment.selectsTestMode(
        arguments: [Self.executable, argument], environment: [:]))
  }

  @Test("The runner's environment key selects test isolation")
  internal func runnerKeySelects() {
    #expect(
      TestCredentialEnvironment.selectsTestMode(
        arguments: [Self.executable], environment: [Self.runnerKey: Self.runnerValue]))
  }

  @Test(
    "An argument that only resembles a selecting one selects nothing",
    arguments: ["--ui-tests", "--ui-test=on", "--virtual-cards", "-XCTest", "test", "contest"])
  internal func resemblingArgumentSelectsNothing(argument: String) {
    #expect(
      !TestCredentialEnvironment.selectsTestMode(
        arguments: [Self.executable, argument], environment: [:]))
  }

  @Test("An executable whose path contains test selects nothing")
  internal func testNamedExecutableSelectsNothing() {
    #expect(
      !TestCredentialEnvironment.selectsTestMode(
        arguments: ["/Applications/Latest Test.app/Contents/MacOS/Test"], environment: [:]))
  }

  @Test(
    "Another runner environment key selects nothing",
    arguments: ["XCTestBundlePath", "XCInjectBundleInto", "SWIFT_TESTING"])
  internal func otherEnvironmentKeySelectsNothing(key: String) {
    #expect(
      !TestCredentialEnvironment.selectsTestMode(
        arguments: [Self.executable], environment: [key: Self.runnerValue]))
  }
}
