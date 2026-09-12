// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore

  /// Concurrent configuration-store access must not trap.
  ///
  /// Launch fires the withdrawal and the displaced-remote cleanup on
  /// separate tasks; both open CryptoTokenKit's configuration
  /// connection, and doing that twice at once trapped inside
  /// `xpc_connection_resume`.
  @Suite(.serialized)
  internal struct DriverConfigurationConcurrencyTests {
    @Test
    internal func concurrentReadsAndWithdrawalsDoNotTrap() async {
      await withTaskGroup(of: Int.self) { group in
        for _ in 0..<16 {
          group.addTask {
            DriverConfiguredCredentials.dropDisplacedRemoteCardConfigurations()
          }
          group.addTask {
            DriverConfiguredCredentials.identityTokenConfigurationCount()
          }
          group.addTask {
            DriverConfiguredCredentials.withdraw()
            return 0
          }
        }
        var finished = 0
        for await _ in group {
          finished += 1
        }
        #expect(finished == 48)
      }
    }
  }

#endif
