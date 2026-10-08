//
//  PillButton.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import SwiftUI

/// A filled pill with a leading Iconly icon, like Claude's "New session":
/// dark in light mode, light in dark mode.
struct PillButton: View {
    let icon: Iconly
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                IconlyIcon(icon, .row)
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .fontDesign(.rounded)
            }
            .foregroundStyle(Color.surfaceBase)
            .padding(.horizontal, Space.xxl)
            .frame(height: 48.0)
            .background(Color.ink, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PillButton(icon: .add, title: "New Session") {}
}
