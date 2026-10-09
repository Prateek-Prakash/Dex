//
//  InkToggle.swift
//  Dex
//
//  Created by Prateek Prakash on 10/9/26.
//

import SwiftUI

/// A switch in ink: the stock thumb is always white, so on an ink track it
/// vanishes in dark mode. On, the track is ink and the thumb the base
/// color; off, the track is gray. Stock size, and stock to VoiceOver.
struct InkToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Capsule()
                .fill(configuration.isOn ? Color.ink : Color.track)
                .frame(width: 51.0, height: 31.0)
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
