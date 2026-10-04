// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

@Suite
internal struct CardExchangeProgressTests {
  @Test("Timeout and late completion preserve the operation correlation")
  internal func lateCompletion() {
    let progress = CardExchangeProgress()
    progress.begin(request: Data([0x10, 0x86]))
    progress.submitted()
    let pending = progress.snapshot()
    #expect(pending.contains("callbackMs=pending"))
    progress.timedOut()
    #expect(progress.completed())
    let completed = progress.snapshot()
    #expect(completed.contains("waiterTimedOut=true"))
    #expect(!completed.contains("callbackMs=pending"))
    #expect(pending.split(separator: " ").first == completed.split(separator: " ").first)
  }

  @Test("Progress never records command parameters, payloads, or sizes")
  internal func metadataOnly() {
    let progress = CardExchangeProgress()
    progress.begin(request: Data([0x00, 0x20]))
    let snapshot = progress.snapshot()
    #expect(snapshot.contains("ins=20"))
    #expect(!snapshot.contains("tx="))
    #expect(!snapshot.contains("request="))
    #expect(!snapshot.contains("payload="))
    #expect(!progress.completed())
    progress.submitted()
    #expect(!progress.snapshot().contains("submitReturnMs=pending"))
  }
}
