//
//  LiveMark.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import SwiftUI

/// The main screen's Live Photo mark. While the server is reachable it comes
/// alive: its layers breathe, an AI-style gradient (blue, purple, pink,
/// orange) turns around it, and a soft glow of the same colors sits behind.
/// The color and glow fade in on connecting and out on losing it; otherwise
/// it rests, plain gray.
struct LiveMark: View {
    let isAlive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 is gray, 1 is fully colored; animated between them.
    @State private var color: Double = 0

    var body: some View {
        TimelineView(.animation(paused: !isAlive || reduceMotion)) { context in
            // One turn every 6 seconds.
            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6 * 360
            ZStack {
                symbol
                    .foregroundStyle(glow(at: angle))
                    .blur(radius: 18.0)
                    .opacity(0.7 * color)
                symbol
                    .foregroundStyle(.tertiary)
                    .opacity(1 - color)
                symbol
                    .foregroundStyle(glow(at: angle))
                    .opacity(color)
            }
            .symbolEffect(.breathe.pulse.byLayer, options: .repeat(.continuous), isActive: isAlive && !reduceMotion)
        }
        .onAppear { color = isAlive ? 1 : 0 }
        .onChange(of: isAlive) {
            withAnimation(.easeInOut(duration: 1.2)) {
                color = isAlive ? 1 : 0
            }
        }
    }

    private var symbol: some View {
        // iconly-exception: the Live Photo mark, Dex's one SF Symbol (approved 2026-10-06)
        Image(systemName: "livephoto")
            .font(.system(size: 64.0, weight: .light))
    }

    /// The AI colors around the mark, turned to `angle` degrees; the last
    /// stop repeats the first so the seam doesn't show.
    private func glow(at angle: Double) -> AngularGradient {
        AngularGradient(
            colors: Self.glowColors + [Self.glowColors[0]],
            center: .center,
            angle: .degrees(angle)
        )
    }

    static let glowColors: [Color] = [
        Color(light: 0x3B82F6, dark: 0x60A5FA), // blue
        Color(light: 0x8B5CF6, dark: 0xA78BFA), // purple
        Color(light: 0xEC4899, dark: 0xF472B6), // pink
        Color(light: 0xF97316, dark: 0xFB923C), // orange
    ]
}

#Preview {
    VStack(spacing: 40.0) {
        LiveMark(isAlive: true)
        LiveMark(isAlive: false)
    }
}
