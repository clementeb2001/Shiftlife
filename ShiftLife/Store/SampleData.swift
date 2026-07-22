import Foundation

extension AppStore {
    /// Realistic demo data so the app is immediately explorable and the
    /// common-free-time / conflict engines have something to work with.
    static func makeSampleData() -> AppData {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Members – a classic setup: one shift worker, one partner, one child.
        var anna = HouseholdMember(name: "Anna Berg", role: .shiftWorker, color: .blue, isCurrentUser: true)
        anna.isCurrentUser = true
        let jonas = HouseholdMember(name: "Jonas Berg", role: .partner, color: .green)
        var mia = HouseholdMember(name: "Mia Berg", role: .child, color: .orange)
        mia.careInfo = "Grundschule Musterstadt"
        mia.pickups = [
            Pickup(weekday: 2, startMinutes: 15 * 60 + 30, responsibleID: nil, label: "Schule abholen"),      // Mo
            Pickup(weekday: 4, startMinutes: 15 * 60 + 30, responsibleID: jonas.id, label: "Schule abholen"),  // Mi
            Pickup(weekday: 6, startMinutes: 12 * 60, responsibleID: nil, label: "früher Schulschluss"),        // Fr
        ]

        // Shift types (Früh / Spät / Nacht / Bereitschaft / Frei-ish categories).
        let frueh = ShiftType(name: "Frühdienst", abbreviation: "F", color: .teal,
                              startMinutes: 6 * 60, endMinutes: 14 * 60, restHours: 0, counterCategory: .work)
        let spaet = ShiftType(name: "Spätdienst", abbreviation: "S", color: .orange,
                              startMinutes: 14 * 60, endMinutes: 22 * 60, restHours: 0, counterCategory: .work)
        let nacht = ShiftType(name: "Nachtdienst", abbreviation: "N", color: .indigo,
                              startMinutes: 22 * 60, endMinutes: 6 * 60, restHours: 11, counterCategory: .work)
        let bereitschaft = ShiftType(name: "Bereitschaft", abbreviation: "B", color: .purple,
                                     startMinutes: 8 * 60, endMinutes: 20 * 60, restHours: 0, counterCategory: .onCall)

        // Jonas works a regular office job (Mon–Fri 9–17) as a single shift type.
        let buero = ShiftType(name: "Büro", abbreviation: "Bü", color: .green,
                              startMinutes: 9 * 60, endMinutes: 17 * 60, restHours: 0, counterCategory: .work)

        // A rotating pattern F-F-S-S-N-N-Frei.
        let rotation = ShiftPattern(name: "Wechselschicht F-F-S-S-N-N-Frei",
                                    sequence: [frueh.id, frueh.id, spaet.id, spaet.id, nacht.id, nacht.id, nil])

        var instances: [ShiftInstance] = []

        // Apply Anna's rotation for the next 28 days.
        for offset in 0..<28 {
            let day = cal.date(byAdding: .day, value: offset, to: today)!
            let slot = rotation.sequence[offset % rotation.sequence.count]
            if let typeID = slot {
                instances.append(ShiftInstance(memberID: anna.id, shiftTypeID: typeID, date: day))
            }
        }

        // Jonas: office Mon–Fri.
        for offset in 0..<28 {
            let day = cal.date(byAdding: .day, value: offset, to: today)!
            let weekday = cal.component(.weekday, from: day) // 1 = Sun … 7 = Sat
            if weekday != 1 && weekday != 7 {
                instances.append(ShiftInstance(memberID: jonas.id, shiftTypeID: buero.id, date: day))
            }
        }

        // A few events – some will trigger conflicts on purpose.
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(byAdding: .day, value: dayOffset, to: today)
                .flatMap { cal.date(bySettingHour: hour, minute: minute, second: 0, of: $0) }!
        }

        var events: [CalendarEvent] = []

        // Shared dinner in 2 days evening (both should be free-ish depending on shift).
        events.append(CalendarEvent(
            title: "Abendessen mit Freunden", start: at(2, 19), end: at(2, 22),
            category: .shared, visibility: .household,
            memberIDs: [anna.id, jonas.id]))

        // Doctor appointment for Mia during a weekday afternoon – childcare.
        events.append(CalendarEvent(
            title: "Arzttermin Mia", start: at(3, 15), end: at(3, 16),
            category: .childcare, visibility: .household,
            memberIDs: [mia.id], responsibleMemberID: nil))

        // Parents' evening at school – conflicts if Anna has a late shift.
        events.append(CalendarEvent(
            title: "Elternabend Schule", start: at(2, 18), end: at(2, 20),
            category: .appointment, visibility: .household,
            memberIDs: [anna.id, jonas.id]))

        var tasks: [TaskItem] = [
            TaskItem(title: "Großeinkauf erledigen", assigneeID: nil,
                     dueDate: at(4, 12), condition: .nextFreeDay, visibility: .household),
            TaskItem(title: "Auto zur Werkstatt bringen", assigneeID: jonas.id,
                     dueDate: at(5, 9), condition: .none, visibility: .household),
            TaskItem(title: "Mia zum Sport anmelden", assigneeID: anna.id,
                     condition: .none, visibility: .household),
        ]
        tasks[0].isDone = false

        let household = Household(name: "Familie Berg", inviteCode: Self.makeInviteCode())

        return AppData(
            household: household,
            members: [anna, jonas, mia],
            shiftTypes: [frueh, spaet, nacht, bereitschaft, buero],
            patterns: [rotation],
            shiftInstances: instances,
            events: events,
            tasks: tasks,
            hasCompletedOnboarding: false,
            isPremium: false,
            considerRestAfterNight: true
        )
    }

    static func makeInviteCode() -> String {
        let letters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in letters.randomElement()! })
    }
}
