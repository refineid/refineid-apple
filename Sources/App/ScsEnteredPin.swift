// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && FEATURE_SCS
  import CardCore

  /// Noncopyable outcome of an SCS PIN prompt, keeping entered digits
  /// inside `Pin1` / `Pin2` zeroizing stores rather than plain `String`
  /// return values.
  internal enum ScsEnteredPin: ~Copyable {
    case busy
    case cancelled
    case invalidFormat
    case pin1(Pin1)
    case pin2(Pin2)
  }
#endif
