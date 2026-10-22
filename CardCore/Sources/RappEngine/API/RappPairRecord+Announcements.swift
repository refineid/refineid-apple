// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension RappPairRecord {
  /// A session preamble with a fresh routing nonce; build one for every dial.
  public func sessionPreamble(transportProfile: String) throws -> Data {
    guard let key = RoutingKey(record: record),
      let nonce = rappRandomBytes(SessionRouting.nonceSize),
      let tag = key.tag(profile: transportProfile, nonce: nonce)
    else { throw RappBindingError.InvalidInput }
    do {
      return try RoutingPreamble.session(SessionRouting(nonce: nonce, tag: tag))
        .encoded(profile: transportProfile)
    } catch {
      throw RappBindingError.InvalidInput
    }
  }

  /// This pairing's discovery hint for the epoch holding `unixTimeSeconds`.
  public func discoveryHint(unixTimeSeconds: UInt64) throws -> Data {
    guard let key = DiscoveryKey(record: record) else { throw RappBindingError.InvalidInput }
    return key.hint(epoch: DiscoveryRecord.epoch(unixTimeSeconds: unixTimeSeconds))
  }

  /// Whether `txt` is a well-formed session record carrying one of this
  /// pairing's discovery hints.
  public func matchesDiscoveryRecord(_ txt: [RappTxtEntry], unixTimeSeconds: UInt64) -> Bool {
    guard let parsed = DiscoveryRecord.parse(txt.map { ($0.key, $0.value) }),
      let key = DiscoveryKey(record: record)
    else { return false }
    return key.matches(parsed, epoch: DiscoveryRecord.epoch(unixTimeSeconds: unixTimeSeconds))
  }

  /// This pairing's withdrawal hint for `instance` at `unixTimeSeconds`.
  public func withdrawalHint(instance: String, unixTimeSeconds: UInt64) throws -> Data {
    guard let name = InstanceName(instance), let key = WithdrawalKey(record: record) else {
      throw RappBindingError.InvalidInput
    }
    return key.hint(
      instance: name, counter: WithdrawnRecord.counter(unixTimeSeconds: unixTimeSeconds))
  }

  /// Whether `txt` is a withdrawn record that announces this pairing on
  /// `instance`.
  public func matchesWithdrawnRecord(
    instance: String, txt: [RappTxtEntry], unixTimeSeconds: UInt64
  ) -> Bool {
    guard let name = InstanceName(instance),
      let parsed = WithdrawnRecord.parse(txt.map { ($0.key, $0.value) }),
      let key = WithdrawalKey(record: record)
    else { return false }
    return key.matches(
      parsed, instance: name, counter: WithdrawnRecord.counter(unixTimeSeconds: unixTimeSeconds))
  }
}
