//
//  LiveMark.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import SwiftUI

/// The main screen's mark, drawn in code: a dotted outer ring, a solid ring
/// and a center dot, after the Live Photo symbol. While the server is
/// reachable it comes alive: ripples leave the center dot and fade before
/// the solid ring, the rings breathe, an AI-style gradient (blue, purple,
/// pink, orange) turns around it, a halo behind the dotted ring brightens
/// and dims with the dots, and a soft glow sits behind it all. The color and
/// motion fade in on connecting and out on losing it; otherwise it rests,
/// plain gray, as the classic dot.
struct LiveMark: View {
    let isAlive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 is gray and still, 1 is fully colored and moving; animated between them.
    @State private var life: Double = 0
    /// True once the fade to gray has finished; the clock stops only then,
    /// so ripples fade out instead of freezing.
    @State private var isAtRest = true
    /// Counts fades, so a finished fade knows whether a newer one started.
    @State private var fade = 0

    /// The mark's width, close to the 64pt Live Photo symbol it replaces.
    static let size: CGFloat = 76.0

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || (isAtRest && !isAlive))) { context in
            LiveMarkCanvas(
                time: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate,
                life: life
            )
        }
        // Room for the glow to fade out fully, without taking up layout: at
        // twice the size the blur was cut off, a faint hard edge around it.
        .frame(width: Self.size * 4, height: Self.size * 4)
        .frame(width: Self.size, height: Self.size)
        .accessibilityHidden(true)
        .onAppear {
            life = isAlive ? 1 : 0
            isAtRest = !isAlive
        }
        .onChange(of: isAlive) {
            // The clock runs through every fade, either way.
            isAtRest = false
            fade += 1
            let current = fade
            withAnimation(.easeInOut(duration: 1.2)) {
                life = isAlive ? 1 : 0
            } completion: {
                // Only the latest fade settles it: a reconnect mid-fade
                // must not leave a live mark marked at rest.
                if fade == current, life == 0 { isAtRest = true }
            }
        }
    }

    static let glowColors = Color.markGlow

    // MARK: Motion, as pure functions of the clock and `life`.

    /// One breath of the rings, in seconds.
    nonisolated static let breathPeriod = 2.4
    /// How long one ripple takes from the dot to the solid ring.
    nonisolated static let ripplePeriod = 1.8
    nonisolated static let rippleCount = 3

    /// A layer's opacity: dims by up to 35% on each breath; `phase` offsets
    /// layers from each other. Fully opaque at rest.
    nonisolated static func breath(at time: Double, phase: Double = 0, life: Double) -> Double {
        1 - life * 0.35 * (0.5 + 0.5 * sin(time * 2 * .pi / breathPeriod + phase))
    }

    /// The halo's strength: brightest when the dots are, never fully out.
    nonisolated static func halo(at time: Double) -> Double {
        1 - 0.6 * (0.5 + 0.5 * sin(time * 2 * .pi / breathPeriod))
    }

    /// Each ripple's progress from the dot (0) to the solid ring (1) and
    /// opacity: it fades in quickly, then out as it grows. None at rest.
    nonisolated static func ripples(at time: Double, life: Double) -> [(progress: Double, opacity: Double)] {
        guard life > 0 else { return [] }
        return (0..<rippleCount).map { index in
            let cycle = time / ripplePeriod + Double(index) / Double(rippleCount)
            let progress = cycle - cycle.rounded(.down)
            return (progress, life * pow(1 - progress, 1.4) * min(1, progress * 6))
        }
    }
}

/// One frame of the mark. Animatable, so `life` steps smoothly through the
/// 1.2 s fade instead of jumping.
private struct LiveMarkCanvas: View, Animatable {
    var time: Double
    var life: Double

    var animatableData: Double {
        get { life }
        set { life = newValue }
    }

    var body: some View {
        Canvas { context, canvas in
            let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let size = LiveMark.size
            // The gradient turns once every 6 seconds.
            let turn = time.truncatingRemainder(dividingBy: 6) / 6 * 360
            let color = GraphicsContext.Shading.conicGradient(
                Gradient(colors: LiveMark.glowColors + [LiveMark.glowColors[0]]),
                center: center,
                angle: .degrees(turn)
            )

            if life > 0 {
                // The halo: a faint, narrow band under the dotted ring, blurred.
                var halo = context
                halo.addFilter(.blur(radius: size * 0.06))
                halo.opacity = 0.35 * LiveMark.halo(at: time) * life
                halo.stroke(circle(center, size / 2 * 0.92), with: color, lineWidth: size * 0.06)

                // The soft glow behind the whole mark: one blurred disc, a
                // single light. Blurring the thin dots and ring left it lumpy.
                var glow = context
                glow.addFilter(.blur(radius: size * 0.28))
                glow.opacity = 0.3 * life
                glow.fill(circle(center, size / 2 * 0.8), with: color)
            }

            var gray = context
            gray.opacity = 1 - life
            draw(in: gray, center: center, with: .style(.tertiary))

            var colored = context
            colored.opacity = life
            draw(in: colored, center: center, with: color)
        }
    }

    /// The mark's shapes, each layer at its own opacity.
    private func draw(in context: GraphicsContext, center: CGPoint, with shading: GraphicsContext.Shading) {
        let size = LiveMark.size
        let radius = size / 2

        // Dotted outer ring.
        var dots = context
        dots.opacity *= LiveMark.breath(at: time, life: life)
        let dotCount = 28
        var dotPath = Path()
        for index in 0..<dotCount {
            let angle = Double(index) / Double(dotCount) * 2 * .pi
            let point = CGPoint(x: center.x + cos(angle) * radius * 0.92, y: center.y + sin(angle) * radius * 0.92)
            dotPath.addPath(circle(point, size * 0.019))
        }
        dots.fill(dotPath, with: shading)

        // Solid ring.
        var ring = context
        ring.opacity *= LiveMark.breath(at: time, phase: 1.4, life: life)
        ring.stroke(circle(center, radius * 0.64), with: shading, lineWidth: size * 0.032)

        // Center dot, swelling slightly while alive.
        let dotRadius = radius * 0.26
        context.fill(circle(center, dotRadius * (1 + 0.06 * life * sin(time * 2.6))), with: shading)

        // Ripples from the dot, gone before the solid ring.
        for ripple in LiveMark.ripples(at: time, life: life) {
            var layer = context
            layer.opacity *= ripple.opacity
            let rippleRadius = dotRadius + ripple.progress * (radius * 0.58 - dotRadius)
            layer.stroke(circle(center, rippleRadius), with: shading, lineWidth: size * 0.022)
        }
    }

    private func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}

#Preview {
    // spacing: preview only, room for both marks' glow
    VStack(spacing: 40.0) {
        LiveMark(isAlive: true)
        LiveMark(isAlive: false)
    }
}
