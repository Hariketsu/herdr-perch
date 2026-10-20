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
        #expect(preferences.compactStyle == .dots)
        #expect(preferences.listStyle == .heroAndRows)
        #expect(preferences.autoExpandOnBlocked)
        #expect(preferences.displayPlacement == .builtInNotch)
        #expect(!preferences.launchAtLogin)
        #expect(preferences.followReduceMotion == false)
    }

    @Test func defaultsAndMissingKeys() throws {
        expectDefaults(Preferences())
        try withDefaults { defaults, _ in
            expectDefaults(Preferences.load(from: defaults))
        }
    }

    @Test func allSixKeysAndRoundTrip() throws {
        try withDefaults { defaults, name in
            var preferences = Preferences()
            preferences.compactStyle = .counts
            preferences.listStyle = .rowsOnly
            preferences.autoExpandOnBlocked = false
            preferences.displayPlacement = .mainDisplay
            preferences.launchAtLogin = true
            preferences.followReduceMotion = true
            preferences.save(to: defaults)
            #expect(Preferences.load(from: defaults) == preferences)
            let persisted = try #require(defaults.persistentDomain(forName: name))
            #expect(Set(persisted.keys) == ["compactStyle", "listStyle", "autoExpandOnBlocked", "displayPlacement", "launchAtLogin", "followReduceMotion"])
            #expect(defaults.string(forKey: "compactStyle") == "C")
            #expect(defaults.string(forKey: "listStyle") == "rowsOnly")
            #expect(defaults.object(forKey: "autoExpandOnBlocked") as? Bool == false)
            #expect(defaults.string(forKey: "displayPlacement") == "mainDisplay")
            #expect(defaults.object(forKey: "launchAtLogin") as? Bool == true)
            #expect(defaults.object(forKey: "followReduceMotion") as? Bool == true)
        }
    }

    @Test func loadsLiteralKeysIndependentlyOfSave() throws {
        try withDefaults { defaults, _ in
            defaults.set("A", forKey: "compactStyle")
            defaults.set("rowsOnly", forKey: "listStyle")
            defaults.set(false, forKey: "autoExpandOnBlocked")
            defaults.set("mainDisplay", forKey: "displayPlacement")
            defaults.set(true, forKey: "launchAtLogin")
            let preferences = Preferences.load(from: defaults)
            #expect(preferences.compactStyle == .birdCount)
            #expect(preferences.listStyle == .rowsOnly)
            #expect(!preferences.autoExpandOnBlocked)
            #expect(preferences.displayPlacement == .mainDisplay)
            #expect(preferences.launchAtLogin)
            #expect(preferences.followReduceMotion == false) // Existing five-key preferences omit the new key.
        }
    }

    @Test func unknownEnumValuesFallBackWithoutLosingRecognizedSettings() throws {
        try withDefaults { defaults, _ in
            defaults.set("future-style", forKey: "compactStyle")
            defaults.set("future-list", forKey: "listStyle")
            defaults.set("future-screen", forKey: "displayPlacement")
            defaults.set(false, forKey: "autoExpandOnBlocked")
            defaults.set(true, forKey: "launchAtLogin")
            let preferences = Preferences.load(from: defaults)
            #expect(preferences.compactStyle == .dots)
            #expect(preferences.listStyle == .heroAndRows)
            #expect(preferences.displayPlacement == .builtInNotch)
            #expect(!preferences.autoExpandOnBlocked)
            #expect(preferences.launchAtLogin)
        }
    }

    @Test func unrecognizedTypesFallBackToDefaults() throws {
        try withDefaults { defaults, _ in
            defaults.set(42, forKey: "compactStyle")
            defaults.set(["rowsOnly"], forKey: "listStyle")
            defaults.set(["enabled": true], forKey: "autoExpandOnBlocked")
            defaults.set(["screen": "main"], forKey: "displayPlacement")
            defaults.set([true], forKey: "launchAtLogin")
            expectDefaults(Preferences.load(from: defaults))
        }
    }

    @Test func savingDefaultsOverwritesEarlierValues() throws {
        try withDefaults { defaults, _ in
            var preferences = Preferences()
            preferences.compactStyle = .birdCount
            preferences.launchAtLogin = true
            preferences.followReduceMotion = true
            preferences.save(to: defaults)
            Preferences().save(to: defaults)
            expectDefaults(Preferences.load(from: defaults))
        }
    }
}
