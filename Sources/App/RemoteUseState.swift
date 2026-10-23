// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import Foundation

  /// The state the remote-use switch shows (STPA CC-95).
  ///
  /// Connected only while a session with the phone is open, waiting while
  /// on with none, and blocked while on with a cause that keeps the phone
  /// from coming. Red and orange mean errors only, so only the blocked
  /// state takes a warning colour; each state is also named in words.
  internal enum RemoteUseState: Equatable, Sendable {
    /// Remote use is on, no session is open, and `blockage` keeps the
    /// phone from coming.
    case blocked(RemoteUseBlockage)

    /// Remote use is on and a session with the phone is open.
    case connected

    /// Remote use is off: nothing remote runs.
    case off

    /// Remote use is on and no session with the phone is open.
    case waiting

    /// The colour a state's symbol takes.
    internal enum Tone: Equatable, Sendable {
      /// Green: the phone is connected.
      case connected

      /// The secondary text colour, for every normal state.
      case neutral

      /// Orange: an error keeps the phone from coming.
      case warning
    }

    // MARK: Static Properties

    /// What the switch is called, to VoiceOver and in its help.
    internal static var label: String {
      String(localized: "Remote Access")
    }

    // MARK: Computed Properties

    /// The SF Symbol drawing the state: the slash means off, so the symbol
    /// changes only when the switch does, and a change of state while on is
    /// a change of colour alone.
    internal var symbolName: String {
      switch self {
      case .off:
        "key.radiowaves.forward.slash"

      case .waiting, .connected, .blocked:
        "key.radiowaves.forward"
      }
    }

    /// The colour of the symbol.
    internal var tone: Tone {
      switch self {
      case .off, .waiting:
        .neutral

      case .connected:
        .connected

      case .blocked:
        .warning
      }
    }

    /// The state in words, for VoiceOver and the help.
    internal var value: String {
      switch self {
      case .off:
        String(localized: "Off")

      case .waiting:
        String(localized: "On")

      case .connected:
        String(localized: "Phone connected")

      case .blocked(let blockage):
        String(localized: "Blocked: \(blockage.cause)")
      }
    }

    /// The help: the switch's name, then its state.
    internal var help: String {
      Self.label + "\n" + value
    }

    // MARK: Static Functions

    /// The state for the switch `isOn`, whether a session with the phone is
    /// open, and what blocks remote use, if anything.
    ///
    /// An open session shows as connected whatever else is blocked: the
    /// phone it reaches is there.
    internal static func derive(
      isOn: Bool, sessionOpen: Bool, blockage: RemoteUseBlockage?
    ) -> Self {
      guard isOn else { return .off }
      if sessionOpen { return .connected }
      if let blockage { return .blocked(blockage) }
      return .waiting
    }
  }

#endif
