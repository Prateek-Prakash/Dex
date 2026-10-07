//
//  GreetingTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/6/26.
//

import Foundation
import Testing
@testable import Dex

struct GreetingTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test(arguments: [
        (5, Greeting.Slot.morning), (11, .morning),
        (12, .afternoon), (16, .afternoon),
        (17, .evening), (20, .evening),
        (21, .night), (23, .night), (0, .night), (4, .night),
    ])
    func slotByHour(_ hour: Int, _ slot: Greeting.Slot) {
        #expect(Greeting.Slot(hour: hour) == slot)
    }

    @Test func messagesAreStatementsNotQuestions() {
        #expect(Greeting.Slot.allCases.flatMap(\.messages).allSatisfy { !$0.contains("?") })
    }

    @Test func messageHoldsWithinASlot() {
        #expect(Greeting.text(for: date(7, 12), calendar: calendar) == Greeting.text(for: date(7, 16, 59), calendar: calendar))
    }

    @Test func nightKeepsItsMessagePastMidnight() {
        #expect(Greeting.text(for: date(7, 23), calendar: calendar) == Greeting.text(for: date(8, 2), calendar: calendar))
    }

    // Over a week every message in every slot comes up.
    @Test func everyMessageShowsWithinAWeek() {
        for hour in [6, 13, 18, 22] {
            let shown = Set((5...11).map { Greeting.text(for: date($0, hour), calendar: calendar) })
            #expect(shown == Set(Greeting.Slot(hour: hour).messages), "slot at \(hour):00")
        }
    }

    @Test func everySlotOfAWeekPicksFromItsPool() {
        for day in 5...11 {
            for hour in [6, 13, 18, 22] {
                let text = Greeting.text(for: date(day, hour), calendar: calendar)
                #expect(Greeting.Slot(hour: hour).messages.contains(text))
            }
        }
    }
}
