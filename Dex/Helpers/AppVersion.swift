//
//  AppVersion.swift
//  Dex
//
//  Created by Prateek Prakash on 10/15/26.
//

import Foundation

/// User-visible version label ("1.0.0+1": marketing version + build, matching
/// the release tag). Read from the bundle so it follows MARKETING_VERSION and
/// CURRENT_PROJECT_VERSION; a Bump Build updates it with no code change.
enum AppVersion {
    static var label: String { label(from: Bundle.main.infoDictionary) }

    static func label(from info: [String: Any]?) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version)+\(build)"
    }
}
