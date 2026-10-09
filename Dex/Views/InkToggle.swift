//
//  InkToggle.swift
//  Dex
//
//  Created by Prateek Prakash on 10/9/26.
//

import SwiftUI
import UIKit

/// A switch in ink: the stock thumb is always white, so on an ink track it
/// vanishes in dark mode. On, the track is ink and the thumb the base
/// color; off, the track is gray. Stock size, and stock to VoiceOver.
struct InkToggleStyle: ToggleStyle {
    /// The system switch's size on this iOS: 51×31 up to iOS 18, 61×28 from
    /// iOS 26. Measured, so a row is exactly as tall as one with a stock switch.
    @MainActor static let trackSize = UISwitch().intrinsicContentSize

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Capsule()
                .fill(configuration.isOn ? Color.ink : Color.track)
                .frame(width: Self.trackSize.width, height: Self.trackSize.height)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.surfaceBase)
                        .padding(Space.xxs)
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.2)) {
                configuration.isOn.toggle()
            }
        }
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

extension ToggleStyle where Self == InkToggleStyle {
    static var ink: InkToggleStyle { InkToggleStyle() }
}
