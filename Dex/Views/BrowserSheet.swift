//
//  BrowserSheet.swift
//  Dex
//
//  Created by Prateek Prakash on 10/9/26.
//

import SafariServices
import SwiftUI

/// A web page opened from a chat, shown in Safari's in-app browser in a
/// sheet, as Claude does.
struct BrowserLink: Identifiable {
    let url: URL
    var id: URL { url }

    /// Web pages open in the sheet; anything else (mail, phone, an app's
    /// own links) goes to the system as before.
    static func opensInApp(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }
}

/// Safari's in-app browser.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let safari = SFSafariViewController(url: url)
        safari.preferredControlTintColor = UIColor(Color.ink)
        safari.dismissButtonStyle = .close
        return safari
    }

    func updateUIViewController(_ safari: SFSafariViewController, context: Context) {}
}
