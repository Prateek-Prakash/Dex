//
//  WaveformView.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import SwiftUI

/// The live waveform while dictating, measured from Claude's: 3pt bars with
/// round caps on a 6pt pitch, silence as round dots, the loudest 36pt tall,
/// centered on one line. It starts empty: each sample enters at
/// the right, by the stop button, and the line slides left between samples,
/// so it moves across instead of stepping.
struct WaveformView: View {
    /// Loudness, oldest first, 0 to 1.
    let levels: [CGFloat]
    /// When the newest level arrived.
    let lastSample: Date
    var interval: TimeInterval = Dictation.sampleInterval

    static let barWidth: CGFloat = 3.0
    static let pitch: CGFloat = 6.0
    /// Claude's round buttons are 36pt; its loudest bars reach as tall.
    static let maxHeight: CGFloat = 36.0
    /// Silence: a round dot as wide as a bar.
    static let minHeight: CGFloat = 3.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            Canvas { canvas, size in
                // How far the line has slid toward the next sample.
                let progress = reduceMotion ? 0 : min(max(context.date.timeIntervalSince(lastSample) / interval, 0), 1)
                for bar in Self.bars(levels: levels, width: size.width, progress: progress) {
                    // A stroked line with round caps: a true half circle at
                    // each end, which a 3pt-wide filled capsule doesn't draw.
                    let reach = max(bar.height - Self.barWidth, 0) / 2
                    var line = Path()
                    line.move(to: CGPoint(x: bar.x, y: size.height / 2 - reach))
                    line.addLine(to: CGPoint(x: bar.x, y: size.height / 2 + reach))
                    canvas.stroke(line, with: .color(.primary),
                                  style: StrokeStyle(lineWidth: Self.barWidth, lineCap: .round))
                }
            }
        }
        .frame(height: Self.maxHeight)
        .accessibilityElement()
        .accessibilityLabel("Recording")
    }

    struct Bar: Equatable {
        let x: CGFloat
        let height: CGFloat
    }

    /// Bars right to left from the newest level, one per pitch, as many as
    /// fit; before any sound, nothing. `progress` (0 to 1) slides them left
    /// toward the next sample.
    static func bars(levels: [CGFloat], width: CGFloat, progress: Double) -> [Bar] {
        let count = min(Int(width / pitch), levels.count)
        guard count > 0 else { return [] }
        let shift = CGFloat(progress) * pitch
        return (0..<count).compactMap { index in
            let level = levels[levels.count - 1 - index]
            let x = width - pitch / 2 - CGFloat(index) * pitch - shift
            guard x >= barWidth / 2 else { return nil }
            return Bar(x: x, height: max(minHeight, min(level, 1) * maxHeight))
        }
    }
}
