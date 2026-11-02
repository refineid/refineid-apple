// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import CardCore

/// A synthetic card on an antenna: it refuses the FINEID application with
/// a configured status word until PACE has run, plays PACE through a
/// ``SyntheticPaceCard``, and answers every command after it through a
/// ``SecureMessagingMirrorCard`` built on the session keys the card itself
/// derived.
///
/// A personal card refuses with security status not satisfied, an
/// organization card with conditions of use not satisfied (FINEID S1 v4.0,
/// organizational cards, section 2.1).
internal final class SyntheticAntennaCard<Curve: PaceCurve>: CardChannel {
  private let pace: SyntheticPaceCard<Curve>
  private let refusal: StatusWord
  private let afterPace: [(payload: Data, statusWord: Data)]
  private var secure: SecureMessagingMirrorCard?

  /// The plain command of the application select, as the terminal sends it.
  private let applicationSelect = CommandApdu.selectApplication(.fineidApplication).encoded

  /// Every plain command the card answered before PACE, in order.
  internal private(set) var plainCommands: [Data] = []

  /// The secure-messaging card, once PACE has completed.
  internal var secureCard: SecureMessagingMirrorCard? { secure }

  internal var readChunkLength: ReadChunkLength { .plain }

  /// A card that refuses the application with `refusal` before PACE and
  /// answers `afterPace` in turn inside the channel.
  internal init(
    pace configuration: SyntheticPaceCard<Curve>.Configuration,
    refusal: StatusWord,
    afterPace: [(payload: Data, statusWord: Data)]
  ) {
    self.pace = SyntheticPaceCard(configuration)
    self.refusal = refusal
    self.afterPace = afterPace
  }

  /// The two octets of `statusWord`.
  internal static func octets(_ statusWord: StatusWord) -> Data {
    withUnsafeBytes(of: statusWord.encoded.bigEndian) { Data($0) }
  }

  internal func transmit(_ payload: Data) throws -> Data {
    if let secure {
      return try secure.transmit(payload)
    }
    plainCommands.append(payload)
    if payload == applicationSelect {
      return Self.octets(refusal)
    }
    let answer = try pace.transmit(payload)
    if pace.generalAuthenticateCount == SyntheticPaceCardValues.paceRounds,
      let keys = pace.sessionKeys
    {
      secure = SecureMessagingMirrorCard(
        encryptionKey: keys.encryptionKey,
        macKey: keys.macKey,
        responses: afterPace,
        fault: .honest)
    }
    return answer
  }
}
