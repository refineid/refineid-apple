// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// Wall and continuous clocks in the millisecond units RAPP uses.
  public struct RappPlatformClock: Sendable {
    private static let nanosecondsPerMillisecond: UInt64 = 1_000_000
    private static let secondsPerMillisecond = 1_000.0

    /// Nanoseconds per tick of the continuous clock.
    private static let timebase: (numerator: UInt64, denominator: UInt64) = {
      var info = mach_timebase_info_data_t()
      mach_timebase_info(&info)
      return (UInt64(info.numer), UInt64(info.denom))
    }()

    /// Creates a system-backed clock.
    public init() {
      // platform default
    }

    /// Milliseconds since the Unix epoch; moves with wall-clock changes.
    public func wallMilliseconds() -> UInt64 {
      UInt64(Date().timeIntervalSince1970 * Self.secondsPerMillisecond)
    }

    /// Milliseconds of the continuous clock: monotonic, and advancing
    /// while the device sleeps and the process is suspended, as operation
    /// deadlines require (RAPP v26.10.22 §8.1 item 2).
    public func monotonicMilliseconds() -> UInt64 {
      let ticks = mach_continuous_time()
      let (scaled, overflow) = ticks.multipliedReportingOverflow(by: Self.timebase.numerator)
      let nanoseconds = overflow ? UInt64.max : scaled / Self.timebase.denominator
      return nanoseconds / Self.nanosecondsPerMillisecond
    }
  }
#endif
