//
//  BindingExt.swift
//  Dex
//
//  Created by Prateek Prakash on 1/26/25.
//

import SwiftUI

extension Binding where Value == Bool {
    var not: Binding<Value> {
        Binding<Value>(
            get: { !self.wrappedValue },
            set: { self.wrappedValue = !$0 }
        )
    }
}
