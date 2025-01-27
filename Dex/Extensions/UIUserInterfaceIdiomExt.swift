//
//  UIUserInterfaceIdiomExt.swift
//  Dex
//
//  Created by Prateek Prakash on 1/1/24.
//

import SwiftUI

extension UIUserInterfaceIdiom {
    func toString() -> String {
        switch (self) {
        case .unspecified:
            return "Unspecified"
        case .phone:
            return "Phone"
        case .pad:
            return "Pad"
        case .tv:
            return "TV"
        case .carPlay:
            return "CarPlay"
        case .mac:
            return "Mac"
        case .vision:
            return "Vision"
        default:
            return "Unknown"
        }
    }
}
