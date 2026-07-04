import Foundation
import QuickieCore

/// One-time forward-migration of the Event/Reminder capture settings onto the
/// declared schema's single dynamic-choice keys (ADR 0020; issue #69). Issue #69
/// retired the `event.askCalendar`/`event.defaultCalendarID` and
/// `reminder.askList`/`reminder.defaultListID` pairs for a single `event.calendar` /
/// `reminder.list` value; without this step an install that had "don't ask, save
/// silently" configured would read the new key's empty default and silently flip
/// back to "ask every time" on upgrade.
///
/// Mirrors the repo's existing one-time-flag precedent
/// (`QuickieStore.seedDefaultCustomActions`): flag-gated so it runs once, and
/// idempotent. The routing translation itself lives in Core
/// (`SettingsChoice.migratedSelection`, covered by `swift test`); this owns only the
/// `UserDefaults` edge — the same `.standard` store the capture settings' `@AppStorage`
/// reads from.
enum SettingsMigration {
    /// Set once the migration has run, so the old keys are read forward exactly once.
    private static let flagKey = "settings.dynamicChoiceMigrated"

    private static let oldEventAskKey = "event.askCalendar"
    private static let oldEventDefaultKey = "event.defaultCalendarID"
    private static let oldReminderAskKey = "reminder.askList"
    private static let oldReminderDefaultKey = "reminder.defaultListID"

    /// Seeds the new dynamic-choice keys from any retired ones, then clears the old
    /// keys. Runs before `RootView`'s `@AppStorage` first read (from `QuickieApp.init`),
    /// so the very first capture after an upgrade already sees the migrated routing.
    static func migrateDynamicChoices(in defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: flagKey) else { return }

        migrate(in: defaults, askKey: oldEventAskKey, defaultKey: oldEventDefaultKey, newKey: SettingsKey.eventCalendar)
        migrate(in: defaults, askKey: oldReminderAskKey, defaultKey: oldReminderDefaultKey, newKey: SettingsKey.reminderList)

        defaults.set(true, forKey: flagKey)
    }

    /// Translates one retired ask/default-id pair into the new single key. Only seeds
    /// when the old ask key was actually written and the new key is still unset (so a
    /// value the user set post-upgrade is never clobbered); an ask-on state maps to
    /// the empty default and needs no write. The old keys are always cleared.
    private static func migrate(in defaults: UserDefaults, askKey: String, defaultKey: String, newKey: String) {
        defer {
            defaults.removeObject(forKey: askKey)
            defaults.removeObject(forKey: defaultKey)
        }

        guard defaults.object(forKey: askKey) != nil, defaults.object(forKey: newKey) == nil else { return }

        let migrated = SettingsChoice.migratedSelection(
            ask: defaults.bool(forKey: askKey),
            defaultID: defaults.string(forKey: defaultKey) ?? ""
        )
        // Empty is the fresh default (`.ask`); only a non-default routing is written.
        if !migrated.isEmpty {
            defaults.set(migrated, forKey: newKey)
        }
    }
}
