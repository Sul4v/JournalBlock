import Foundation
import Observation
import SwiftUI
import AlarmKit
import AppIntents

/// A real alarm — AlarmKit rings through silent mode and Focus, which a local
/// notification cannot. Waking the user is the trigger for the whole ritual, so
/// it deserves the real API rather than a notification pretending to be one.
@Observable
final class AlarmService {
    static let shared = AlarmService()

    private(set) var authorizationState: AlarmManager.AuthorizationState = .notDetermined
    private(set) var lastError: String?
    private(set) var scheduledAlarmID: UUID?

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let manager = AlarmManager.shared

    private init() {
        authorizationState = manager.authorizationState
        if let raw = defaults.string(forKey: Self.alarmIDKey) {
            scheduledAlarmID = UUID(uuidString: raw)
        }
    }

    var isAuthorized: Bool { authorizationState == .authorized }

    // MARK: - Authorization

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let state = try await manager.requestAuthorization()
            authorizationState = state
            lastError = state == .denied ? "Alarm permission was declined." : nil
            return state == .authorized
        } catch {
            authorizationState = manager.authorizationState
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Scheduling

    /// Schedules (or reschedules) the daily wake alarm. Every day of the week —
    /// the journal is a daily habit, and a weekday-only alarm quietly breaks it.
    func scheduleWakeAlarm(hour: Int, minute: Int) async {
        if !isAuthorized {
            guard await requestAuthorization() else { return }
        }

        cancelWakeAlarm()

        let alert = AlarmPresentation.Alert(
            title: "Good morning",
            stopButton: AlarmButton(
                text: "Open \(AppConfig.appName)",
                textColor: .white,
                systemImageName: "sun.horizon.fill"
            )
        )

        let attributes = AlarmAttributes<DawnAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: DawnAlarmMetadata(),
            tintColor: Theme.Palette.ember
        )

        let schedule = Alarm.Schedule.relative(
            .init(
                time: .init(hour: hour, minute: minute),
                repeats: .weekly(Array(Locale.Weekday.allWeekdays))
            )
        )

        let id = UUID()
        do {
            _ = try await manager.schedule(
                id: id,
                configuration: .alarm(schedule: schedule, attributes: attributes)
            )
            scheduledAlarmID = id
            defaults.set(id.uuidString, forKey: Self.alarmIDKey)
            lastError = nil
        } catch {
            lastError = "Couldn't schedule the alarm: \(error.localizedDescription)"
        }
    }

    func cancelWakeAlarm() {
        guard let id = scheduledAlarmID else { return }
        try? manager.cancel(id: id)
        scheduledAlarmID = nil
        defaults.removeObject(forKey: Self.alarmIDKey)
    }

    private static let alarmIDKey = "dawn.wakeAlarmID"
}

/// AlarmKit requires metadata alongside the presentation; Dawn has a single
/// alarm so there's nothing to distinguish yet.
struct DawnAlarmMetadata: AlarmMetadata {
    init() {}
}

private extension Locale.Weekday {
    static var allWeekdays: [Locale.Weekday] {
        [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
    }
}
