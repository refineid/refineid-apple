// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import RappEngine
import SwiftUI

#if os(iOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

extension RappPairingCoordinator.PairSummary {
  internal var remotePlatformSymbol: String {
    switch role {
    case .requester:
      "iphone"

    case .proxy:
      "desktopcomputer"
    }
  }
}
