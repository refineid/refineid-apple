// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CCryptoki
import Foundation
import Testing

@testable import PKCS11Bridge

/// The YY.M.D.HHMM stamp is read back into the two CK_VERSION fields:
/// the library reports the year and month, the token's firmware the day
/// and the six-minute step since midnight.
@Suite
internal struct ModuleVersionTests {
  @Test
  internal func libraryVersionIsYearAndMonth() {
    let version = ModuleVersion.library(of: "26.10.3.1650")
    #expect(version.major == 26)
    #expect(version.minor == 10)
  }

  @Test
  internal func firmwareVersionIsDayAndSixMinuteStep() {
    let version = ModuleVersion.firmware(of: "26.10.3.1650")
    #expect(version.major == 3)
    #expect(version.minor == 168)
  }

  @Test
  internal func lastMinuteOfTheDayIsTheLastStep() {
    #expect(ModuleVersion.firmware(of: "26.10.3.2359").minor == 239)
  }

  @Test
  internal func firstMinutesOfTheDayAreStepZero() {
    #expect(ModuleVersion.firmware(of: "26.10.3.5").minor == 0)
    #expect(ModuleVersion.firmware(of: "26.10.3.0").minor == 0)
  }

  @Test
  internal func malformedStampReportsZero() {
    #expect(ModuleVersion.firmware(of: "26.10.3").minor == 0)
    #expect(ModuleVersion.firmware(of: "26.10.3.2400").minor == 0)
    #expect(ModuleVersion.firmware(of: "26.10.3.1299").minor == 0)
    #expect(ModuleVersion.library(of: "next").major == 0)
    #expect(ModuleVersion.firmware(of: "26.10.300.1200").major == 0)
  }

  @Test
  internal func stampedTextIsWellFormed() {
    let parts = ModuleVersion.text.split(separator: ".").compactMap { UInt($0) }
    #expect(parts.count == 4)
    let time = parts[3]
    #expect(time / 100 < 24)
    #expect(time % 100 < 60)
    let step = (time / 100 * 60 + time % 100) / 6
    #expect(UInt(ModuleVersion.firmware.minor) == step)
    #expect(ModuleVersion.firmware.major == 3)
  }
}
