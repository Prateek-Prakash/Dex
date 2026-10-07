//
//  DexApp.swift
//  Dex
//
//  Created by Prateek Prakash on 1/22/25.
//

import SwiftData
import SwiftUI

@main
struct DexApp: App {
    init() {
        // iOS's default category can't mix: the first haptic would pause
        // other apps' audio. Only dictation takes it over.
        Dictation.useAmbientAudio()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(Storage.shared)
    }
}
