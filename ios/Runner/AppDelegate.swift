import Flutter
import UIKit
import EventKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let reminderStore = EKEventStore()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      registerReminderChannel(binaryMessenger: controller.binaryMessenger)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LocalRemindersPlugin") {
      registerReminderChannel(binaryMessenger: registrar.messenger())
    }
  }

  private func registerReminderChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.kaiserapps.joey/local_reminders",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleReminderMethod(call, result: result)
    }
  }

  private func handleReminderMethod(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "requestPermission":
      requestReminderAccess(result)
    case "checkPermission":
      result(EKEventStore.authorizationStatus(for: .reminder) == .authorized)
    case "search":
      searchReminders(args, result: result)
    case "create":
      createReminder(args, result: result)
    case "update":
      updateReminder(args, result: result)
    case "delete":
      deleteReminder(args, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func requestReminderAccess(_ result: @escaping FlutterResult) {
    reminderStore.requestAccess(to: .reminder) { granted, error in
      if let error = error {
        result(FlutterError(code: "reminders_permission", message: error.localizedDescription, details: nil))
        return
      }
      result(granted)
    }
  }

  private func ensureReminderAccess(_ completion: @escaping (Bool) -> Void) {
    switch EKEventStore.authorizationStatus(for: .reminder) {
    case .authorized:
      completion(true)
    case .notDetermined:
      reminderStore.requestAccess(to: .reminder) { granted, _ in completion(granted) }
    default:
      completion(false)
    }
  }

  private func searchReminders(_ args: [String: Any], result: @escaping FlutterResult) {
    ensureReminderAccess { [weak self] granted in
      guard let self = self, granted else {
        result(FlutterError(code: "reminders_permission", message: "Reminders permission denied", details: nil))
        return
      }
      let includeCompleted = args["include_completed"] as? Bool ?? false
      let query = (args["query"] as? String)?.lowercased()
      let predicate = includeCompleted
        ? self.reminderStore.predicateForReminders(in: nil)
        : self.reminderStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
      self.reminderStore.fetchReminders(matching: predicate) { reminders in
        let mapped = (reminders ?? [])
          .filter { reminder in
            guard let query = query, !query.isEmpty else { return true }
            return reminder.title.lowercased().contains(query) ||
              (reminder.notes?.lowercased().contains(query) ?? false)
          }
          .map { self.reminderToMap($0) }
        result(["reminders": mapped])
      }
    }
  }

  private func createReminder(_ args: [String: Any], result: @escaping FlutterResult) {
    ensureReminderAccess { [weak self] granted in
      guard let self = self, granted else {
        result(FlutterError(code: "reminders_permission", message: "Reminders permission denied", details: nil))
        return
      }
      let reminder = EKReminder(eventStore: self.reminderStore)
      reminder.calendar = self.reminderStore.defaultCalendarForNewReminders()
      self.applyReminderArgs(args, to: reminder)
      do {
        try self.reminderStore.save(reminder, commit: true)
        result(["created": true, "id": reminder.calendarItemIdentifier])
      } catch {
        result(FlutterError(code: "reminders_create", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func updateReminder(_ args: [String: Any], result: @escaping FlutterResult) {
    ensureReminderAccess { [weak self] granted in
      guard let self = self, granted else {
        result(FlutterError(code: "reminders_permission", message: "Reminders permission denied", details: nil))
        return
      }
      guard let id = args["id"] as? String,
            let reminder = self.reminderStore.calendarItem(withIdentifier: id) as? EKReminder else {
        result(FlutterError(code: "reminders_not_found", message: "Reminder not found", details: nil))
        return
      }
      self.applyReminderArgs(args, to: reminder)
      do {
        try self.reminderStore.save(reminder, commit: true)
        result(["updated": true, "id": id])
      } catch {
        result(FlutterError(code: "reminders_update", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func deleteReminder(_ args: [String: Any], result: @escaping FlutterResult) {
    ensureReminderAccess { [weak self] granted in
      guard let self = self, granted else {
        result(FlutterError(code: "reminders_permission", message: "Reminders permission denied", details: nil))
        return
      }
      guard let id = args["id"] as? String,
            let reminder = self.reminderStore.calendarItem(withIdentifier: id) as? EKReminder else {
        result(FlutterError(code: "reminders_not_found", message: "Reminder not found", details: nil))
        return
      }
      do {
        try self.reminderStore.remove(reminder, commit: true)
        result(["deleted": true, "id": id])
      } catch {
        result(FlutterError(code: "reminders_delete", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func applyReminderArgs(_ args: [String: Any], to reminder: EKReminder) {
    if let title = args["title"] as? String {
      reminder.title = title
    }
    if let notes = args["notes"] as? String {
      reminder.notes = notes
    }
    if let completed = args["completed"] as? Bool {
      reminder.isCompleted = completed
    }
    if let dueDateString = args["due_date"] as? String {
      let formatter = ISO8601DateFormatter()
      if let date = formatter.date(from: dueDateString) {
        reminder.dueDateComponents = Calendar.current.dateComponents(
          [.year, .month, .day, .hour, .minute],
          from: date
        )
      }
    }
  }

  private func reminderToMap(_ reminder: EKReminder) -> [String: Any?] {
    let dueDate = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
    return [
      "id": reminder.calendarItemIdentifier,
      "title": reminder.title,
      "notes": reminder.notes,
      "completed": reminder.isCompleted,
      "dueDate": dueDate.map { ISO8601DateFormatter().string(from: $0) },
      "calendarTitle": reminder.calendar.title
    ]
  }
}
