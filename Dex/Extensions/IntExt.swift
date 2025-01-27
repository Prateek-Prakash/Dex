//
//  IntExt.swift
//  Dex
//
//  Created by Prateek Prakash on 1/26/25.
//

import Foundation

extension Int {
    var byteSize: String {
        return ByteCountFormatter().string(fromByteCount: Int64(self))
    }
}
