// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) || os(macOS)

  import CardCore

  extension ActivationScheme {
    internal var localizedName: String {
      VirtualIDCardOverlayLocalization.activationSchemeName(self)
    }
  }

#endif
