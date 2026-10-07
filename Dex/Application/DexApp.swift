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
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(Storage.shared)
    }
}
