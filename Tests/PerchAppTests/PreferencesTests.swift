import Foundation
import Testing
@testable import PerchApp

@Suite struct PreferencesTests {
    private func withDefaults(_ body: (UserDefaults, String) throws -> Void) throws {
        let name = "perch-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults, name)
    }

    private func expectDefaults(_ preferences: Preferences) {
        #expect(preferences.compactStyle == .birdCount)
        #expect(preferences.listStyle == .grouped)
        #expect(preferences.blockedAlert == .peek)
        #expect(preferences.finishedAlert == .peek)
        #expect(preferences.displayPlacement == .builtInNotch)
        #expect(!preferences.launchAtLogin)
        #expect(preferences.followReduceMotion == false)
        #expect(preferences.cleanTitles)
    }

    @Test func defaultsAndMissingKeys() throws {
        expectDefaults(Preferences())
        try withDefaults { defaults, _ in
            expectDefaults(Preferences.load(from: defaults))
        }
    }

    @Test func allEightKeysAndRoundTrip() throws {
        try withDefaults { defaults, name in
            var preferences = Preferences()
            preferences.compactStyle = .counts
            preferences.listStyle = .rowsOnly
            preferences.blockedAlert = .pulse
            preferences.finishedAlert = .ear
            preferences.displayPlacement = .mainDisplay
            preferences.launchAtLogin = true
            preferences.followReduceMotion = true
            preferences.cleanTitles = false
            preferences.save(to: defaults)
            #expect(Preferences.load(from: defaults) == preferences)
            let persisted = try #require(defaults.persistentDomain(forName: name))
            #expect(Set(persisted.keys) == ["compactStyle", "listStyle", "blockedAlert", "finishedAlert", "displayPlacement", "launchAtLogin", "followReduceMotion", "cleanTitles"])
            #expect(defaults.string(forKey: "compactStyle") == "C")
            #expect(defaults.string(forKey: "listStyle") == "rowsOnly")
            #expect(defaults.string(forKey: "blockedAlert") == "pulse")
            #expect(defaults.string(forKey: "finishedAlert") == "ear")
            #expect(defaults.string(forKey: "displayPlacement") == "mainDisplay")
            #expect(defaults.object(forKey: "launchAtLogin") as? Bool == true)
            #expect(defaults.object(forKey: "followReduceMotion") as? Bool == true)
            #expect(defaults.object(forKey: "cleanTitles") as? Bool == false)
        }
    }

    @Test func loadsLiteralKeysIndependentlyOfSave() throws {
        try withDefaults { defaults, _ in
            defaults.set("B", forKey: "compactStyle")
            defaults.set("rowsOnly", forKey: "listStyle")
            defaults.set("pulse", forKey: "blockedAlert")
            defaults.set("ear", forKey: "finishedAlert")
            defaults.set("mainDisplay", forKey: "displayPlacement")
            defaults.set(true, forKey: "launchAtLogin")
            defaults.set(false, forKey: "cleanTitles")
            let preferences = Preferences.load(from: defaults)
            #expect(preferences.compactStyle == .dots)
            #expect(preferences.listStyle == .rowsOnly)
            #expect(preferences.blockedAlert == .pulse)
            #expect(preferences.finishedAlert == .ear)
            #expect(preferences.displayPlacement == .mainDisplay)
            #expect(preferences.launchAtLogin)
            #expect(preferences.followReduceMotion == false) // Missing key uses its default.
            #expect(!preferences.cleanTitles)
        }
    }

    @Test func groupedListStyleRoundTrip() throws {
        try withDefaults { defaults, _ in
            var preferences = Preferences()
            preferences.listStyle = .grouped
            preferences.save(to: defaults)
            #expect(defaults.string(forKey: "listStyle") == "grouped")
            #expect(Preferences.load(from: defaults) == preferences)
        }
    }

    @Test func unknownEnumValuesFallBackWithoutLosingRecognizedSettings() throws {
        try withDefaults { defaults, _ in
            defaults.set("future-style", forKey: "compactStyle")
            defaults.set("future-list", forKey: "listStyle")
            defaults.set("future-screen", forKey: "displayPlacement")
            defaults.set("pulse", forKey: "blockedAlert")
            defaults.set("ear", forKey: "finishedAlert")
            defaults.set(true, forKey: "launchAtLogin")
            let preferences = Preferences.load(from: defaults)
            #expect(preferences.compactStyle == .birdCount)
            #expect(preferences.listStyle == .grouped)
            #expect(preferences.displayPlacement == .builtInNotch)
            #expect(preferences.blockedAlert == .pulse)
            #expect(preferences.finishedAlert == .ear)
            #expect(preferences.launchAtLogin)
        }
    }

    @Test func unrecognizedTypesFallBackToDefaults() throws {
        try withDefaults { defaults, _ in
            defaults.set(42, forKey: "compactStyle")
            defaults.set(["rowsOnly"], forKey: "listStyle")
            defaults.set(["enabled": true], forKey: "blockedAlert")
            defaults.set(["ear"], forKey: "finishedAlert")
            defaults.set(["screen": "main"], forKey: "displayPlacement")
            defaults.set([true], forKey: "launchAtLogin")
            defaults.set("false", forKey: "cleanTitles")
            expectDefaults(Preferences.load(from: defaults))
        }
    }

    @Test func savingDefaultsOverwritesEarlierValues() throws {
        try withDefaults { defaults, _ in
            var preferences = Preferences()
            preferences.compactStyle = .dots
            preferences.launchAtLogin = true
            preferences.followReduceMotion = true
            preferences.cleanTitles = false
            preferences.save(to: defaults)
            Preferences().save(to: defaults)
            expectDefaults(Preferences.load(from: defaults))
        }
    }
}

extension PreferencesTests {
    @Test(arguments: [false, true])
    func migratesLegacyAutoExpand(_ enabled: Bool) throws {
        try withDefaults { defaults, _ in
            defaults.set(enabled, forKey: "autoExpandOnBlocked")
            #expect(Preferences.load(from: defaults).blockedAlert == (enabled ? .peek : .pulse))
            #expect(Preferences.load(from: defaults).finishedAlert == .peek)
        }
    }

    @Test(arguments: ["peek", "expand", "pulse", "future-alert"])
    func newBlockedKeyTakesPrecedenceOverLegacy(_ raw: String) throws {
        try withDefaults { defaults, _ in
            defaults.set(false, forKey: "autoExpandOnBlocked")
            defaults.set(raw, forKey: "blockedAlert")
            #expect(Preferences.load(from: defaults).blockedAlert == (BlockedAlert(rawValue: raw) ?? .peek))
        }
    }

    @Test func unknownAlertsFallBackToPeek() throws {
        try withDefaults { defaults, _ in
            defaults.set("future-alert", forKey: "blockedAlert")
            defaults.set("future-alert", forKey: "finishedAlert")
            expectDefaults(Preferences.load(from: defaults))
        }
    }

    @Test(arguments: [BlockedAlert.peek, .expand, .pulse], [FinishedAlert.peek, .ear, .off])
    func alertModesRoundTrip(_ blocked: BlockedAlert, _ finished: FinishedAlert) throws {
        try withDefaults { defaults, _ in
            var preferences = Preferences()
            preferences.blockedAlert = blocked
            preferences.finishedAlert = finished
            preferences.save(to: defaults)
            #expect(Preferences.load(from: defaults) == preferences)
        }
    }
}
