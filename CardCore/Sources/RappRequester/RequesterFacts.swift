// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)
  import RappEngine
#endif

/// What the requester knows when it picks the identity line.
///
/// The local card's facts exist wherever the app does. The phone's facts
/// exist where the remote card does, which the app's configurations give
/// to the iOS build, so the package gates them by platform as the project
/// gates them by flag.
public struct RequesterFacts: Equatable, Sendable {
  /// What the token and the card's presence say together.
  public var availability: IdentityAvailability

  /// A card has been present without an identity long enough to warn.
  public var warnsUnavailableCard: Bool

  /// A reader is attached.
  public var readerConnected: Bool

  /// A card is in a reader attached to this computer.
  public var cardPresent: Bool

  #if os(iOS)
    /// The holder has remote use on (hierarchy specification §5.2).
    public var remoteUse = false

    /// A usable pairing with a phone exists.
    public var phonePaired = false

    /// The phone that announced it forgot this computer, by name.
    public var phoneThatForgot: String?

    /// The phone this computer's user has just paired, by name, while the
    /// computer connects to it (RAPP v26.11.8 §4.7).
    public var phoneJustPaired: String?

    /// The platform denies this app the local network: a browse or a dial
    /// to a phone was refused it.
    public var localNetworkDenied = false

    /// The phone's latest `card.status` on the open session; nil without a
    /// session or before its first report.
    public var phoneCardStatus: RappCardStatus?
  #endif

  /// Facts with nothing heard from a phone.
  public init(
    availability: IdentityAvailability,
    warnsUnavailableCard: Bool,
    readerConnected: Bool,
    cardPresent: Bool
  ) {
    self.availability = availability
    self.warnsUnavailableCard = warnsUnavailableCard
    self.readerConnected = readerConnected
    self.cardPresent = cardPresent
  }
}
