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
/// organizational cards, section 2.1). An organization card before PACE
/// also refuses the main file by file identifier with `6985`, and answers
/// the main file by name with nothing usable, after which the phone's
/// platform ends the session (observed on hardware): this card then
/// fails every command.
internal final class SyntheticAntennaCard<Curve: PaceCurve>: CardChannel {
  /// Thrown for every command once the session has ended.
  internal struct SessionEnded: Error, Equatable {}

  private let pace: SyntheticPaceCard<Curve>
  private let refusal: StatusWord
  private let afterPace: [(payload: Data, statusWord: Data)]
  private var secure: SecureMessagingMirrorCard?

  /// Whether the session was ended by a select of the main file by name.
  internal private(set) var tornDown = false

  /// The main file by file identifier and by name, as the terminal sends
  /// them.
  private let mainFileById = CommandApdu.selectFile(
    .mainFile, selectionP1: Iso7816Values.selectByFileIdP1
  ).encoded
  private let mainFileByName = CommandApdu.selectFile(
    .mainFile, selectionP1: Iso7816Values.selectByAidP1
  ).encoded

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
    guard !tornDown else { throw SessionEnded() }
    if let secure {
      return try secure.transmit(payload)
    }
    plainCommands.append(payload)
    if payload == applicationSelect {
      return Self.octets(refusal)
    }
    if refusal == .conditionsNotSatisfied {
      if payload == mainFileById {
        return Self.octets(.conditionsNotSatisfied)
      }
      if payload == mainFileByName {
        tornDown = true
        throw SessionEnded()
      }
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
