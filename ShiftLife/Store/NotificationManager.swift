import Foundation
import UserNotifications

/// Schedules on-device reminders (no backend / remote push needed):
/// upcoming shifts and due tasks. Re-scheduled on foreground and when the
/// notification settings change.
enum NotificationManager {
    private static let prefix = "sl_"

    /// Ask the user for permission. Returns whether it was granted.
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Remove all of our pending reminders and reschedule from current data.
    static func reschedule(_ data: AppData) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        guard data.notifications.enabled else { return }

        let cal = Calendar.current
        let now = Date()
        let horizon = cal.date(byAdding: .day, value: 14, to: now)!
        let pref = data.notifications
        let meID = data.members.first(where: { $0.isCurrentUser })?.id

        // Shift reminders (current user, blocking shifts).
        if pref.shiftReminders, let meID {
            for inst in data.shiftInstances where inst.memberID == meID {
                guard let t = data.shiftTypes.first(where: { $0.id == inst.shiftTypeID }),
                      t.counterCategory.blocksTime else { continue }
                let day = cal.startOfDay(for: inst.date)
                let startMin = inst.startMinutesOverride ?? t.startMinutes
                guard let start = cal.date(byAdding: .minute, value: startMin, to: day),
                      let fire = cal.date(byAdding: .minute, value: -pref.shiftLeadMinutes, to: start) else { continue }
                if fire > now && fire < horizon {
                    schedule(id: "\(prefix)shift_\(inst.id.uuidString)",
                             title: "Dienst bald",
                             body: "\(t.name) startet um \(ShiftType.timeString(startMin)).",
                             at: fire, center: center)
                }
            }
        }

        // Task reminders (open tasks with a due date, at 08:00 that day).
        if pref.taskReminders {
            for task in data.tasks where !task.isDone {
                guard let due = task.dueDate,
                      let fire = cal.date(bySettingHour: 8, minute: 0, second: 0, of: due) else { continue }
                if fire > now && fire < horizon {
                    schedule(id: "\(prefix)task_\(task.id.uuidString)",
                             title: "Aufgabe fällig",
                             body: task.title,
                             at: fire, center: center)
                }
            }
        }
    }

    private static func schedule(id: String, title: String, body: String, at date: Date,
                                 center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
