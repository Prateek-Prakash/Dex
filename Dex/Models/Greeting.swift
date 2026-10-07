//
//  Greeting.swift
//  Dex
//
//  Created by Prateek Prakash on 10/6/26.
//

import Foundation

/// The main screen's greeting: one message per time slot per day, picked
/// from the date rather than at random, so it holds still across launches
/// and turns over with the next slot.
enum Greeting {
    enum Slot: Int, CaseIterable {
        case morning, afternoon, evening, night
        
        /// Morning 5:00–11:59, afternoon 12:00–16:59, evening 17:00–20:59,
        /// night 21:00–4:59.
        init(hour: Int) {
            switch hour {
            case 5..<12: self = .morning
            case 12..<17: self = .afternoon
            case 17..<21: self = .evening
            default: self = .night
            }
        }
        
        var messages: [String] {
            switch self {
            case .morning: ["GOOD MORNING", "RISE AND SHINE", "FRESH START"]
            case .afternoon: ["GOOD AFTERNOON", "AFTERNOON FOCUS", "HALFWAY THERE"]
            case .evening: ["GOOD EVENING", "EVENING THOUGHTS"]
            case .night: ["LATE NIGHT IDEAS", "QUIET HOURS", "MIDNIGHT THOUGHTS"]
            }
        }
    }
    
    static func text(for date: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let slot = Slot(hour: hour)
        // Night runs past midnight: it belongs to the day it started, so the
        // message doesn't change at 0:00.
        let day = slot == .night && hour < 5
            ? calendar.date(byAdding: .day, value: -1, to: date) ?? date
            : date
        // Day number plus slot, so each slot steps through its messages one
        // per day (a seed that multiplies the day by the slot count would
        // land on the same message every day for a slot of two). A fixed
        // formula, not `hashValue`, which changes every launch.
        let dayNumber = calendar.dateComponents([.day], from: .distantPast, to: calendar.startOfDay(for: day)).day ?? 0
        return slot.messages[(dayNumber + slot.rawValue) % slot.messages.count]
    }
}
