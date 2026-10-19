//
//  ContextMeter.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import SwiftUI

/// How much of the model's window the chat fills: a ring that closes as the
/// chat grows, Claude's blue until 80%, then orange, then red past 95%.
/// Sits top right once a chat starts, like Claude's. Tapping it opens a
/// popover with the share as a bar and the counts under it.
struct ContextMeter: View {
    let used: Int
    let total: Int

    @State private var showsUsage = false

    private var share: Double {
        min(1.0, Double(used) / Double(max(total, 1)))
    }

    var body: some View {
        Button {
            showsUsage = true
        } label: {
            ring
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Context")
        .accessibilityValue("\(Int(share * 100)) percent used")
        .popover(isPresented: $showsUsage) {
            ContextUsage(used: used, total: total)
                // A popover on iPhone too, anchored to the ring, not a sheet.
                .presentationCompactAdaptation(.popover)
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.track, lineWidth: 1.5)
            Circle()
                .trim(from: 0.0, to: share)
                .stroke(Self.level(share).color,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90.0))
        }
        // Claude's ring, measured: 19pt across, a 1.5pt line, in a toolbar
        // button's 24pt slot.
        .frame(width: 19.0, height: 19.0)
        .frame(width: 24.0, height: 24.0)
        .contentShape(Rectangle())
    }

    enum Level: Equatable {
        case normal, warning, critical

        var color: Color {
            switch self {
            case .normal: Color.accent
            case .warning: Color.warning
            case .critical: Color.destructive
            }
        }
    }

    /// The ring's color step for `share` of the window used.
    nonisolated static func level(_ share: Double) -> Level {
        if share > 0.95 { return .critical }
        if share > 0.8 { return .warning }
        return .normal
    }
}

/// The ring's popover: the share used, as a percentage and a bar in the
/// ring's color, and the tokens used and the window under it ("16,745 • 65,536").
struct ContextUsage: View {
    let used: Int
    let total: Int

    /// The bar's length; the popover is sized around it.
    private static let barWidth: CGFloat = 200.0

    private var share: Double {
        min(1.0, Double(used) / Double(max(total, 1)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("\(Int((share * 100).rounded()))%")
                .font(.title3)
                .fontWeight(.semibold)
                .fontDesign(.rounded)
                .monospacedDigit()
            Capsule()
                .fill(Color.track)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(ContextMeter.level(share).color)
                        .frame(width: Self.barWidth * share)
                }
                .frame(width: Self.barWidth, height: 6.0)
            Text("\(used.formatted()) • \(total.formatted())")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(Space.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Context \(Int((share * 100).rounded())) percent used, \(used) of \(total) tokens")
    }
}
