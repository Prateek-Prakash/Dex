//
//  ContextMeter.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import SwiftUI

/// How much of the model's window the chat fills: a ring that closes as the
/// chat grows, Claude's blue until 80%, then orange, then red past 95%.
/// Sits top right once a chat starts, like Claude's. Display only for now.
struct ContextMeter: View {
    let used: Int
    let total: Int

    private var share: Double {
        min(1.0, Double(used) / Double(max(total, 1)))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.contextTrack, lineWidth: 1.5)
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
        .accessibilityElement()
        .accessibilityLabel("Context")
        .accessibilityValue("\(Int(share * 100)) percent used")
    }

    enum Level: Equatable {
        case normal, warning, critical

        var color: Color {
            switch self {
            case .normal: Color.contextRing
            case .warning: Color.orange
            case .critical: Color.red
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
