// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)
  import SwiftUI

  /// Runs the timing probe and shows every run, newest first.
  internal struct CardTimingView: View {
    @StateObject private var probe = CardTimingProbe()

    internal var body: some View {
      List {
        controls
        ForEach(probe.runs.reversed(), id: \.identifier) { run in
          section(for: run)
        }
      }
      .navigationTitle("Card Timing")
    }

    private var controls: some View {
      Section {
        Button {
          Task { await probe.run() }
        } label: {
          Label("Time the Card", systemImage: "stopwatch")
        }
        .disabled(probe.isRunning)
        Button {
          UIPasteboard.general.string = probe.report
        } label: {
          Label("Copy Report", systemImage: "doc.on.doc")
        }
        .disabled(probe.runs.isEmpty)
        Button(role: .destructive) {
          probe.clear()
        } label: {
          Label("Clear", systemImage: "trash")
        }
        .disabled(probe.runs.isEmpty)
      } header: {
        Text(CardTimingProbe.device)
      }
    }

    private func section(for run: CardTimingProbe.Run) -> some View {
      Section {
        ForEach(run.exchanges, id: \.identifier) { exchange in
          LabeledContent(exchange.name) {
            Text("\(exchange.milliseconds, format: .number.precision(.fractionLength(1))) ms")
              .monospacedDigit()
          }
        }
        LabeledContent("Field") {
          Text("\(run.fieldMilliseconds, format: .number.precision(.fractionLength(1))) ms")
            .monospacedDigit()
        }
        Text(run.outcome)
          .font(.footnote)
      } header: {
        Text(run.started, format: .dateTime.hour().minute().second())
      }
    }
  }
#endif
