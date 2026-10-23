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
        #expect(preferences.peekOnFinished)
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

    @Test func allSixKeysAndRoundTrip() throws {
        try withDefaults { defaults, name in
            var preferences = Preferences()
            preferences.compactStyle = .counts
            preferences.peekOnFinished = false
            preferences.displayPlacement = .mainDisplay
            preferences.launchAtLogin = true
            preferences.followReduceMotion = true
            preferences.cleanTitles = false
            preferences.save(to: defaults)
            #expect(Preferences.load(from: defaults) == preferences)
            let persisted = try #require(defaults.persistentDomain(forName: name))
            #expect(Set(persisted.keys) == ["compactStyle", "peekOnFinished", "displayPlacement", "launchAtLogin", "followReduceMotion", "cleanTitles"])
            #expect(defaults.string(forKey: "compactStyle") == "C")
            #expect(defaults.object(forKey: "peekOnFinished") as? Bool == false)
            #expect(defaults.string(forKey: "displayPlacement") == "mainDisplay")
            #expect(defaults.object(forKey: "launchAtLogin") as? Bool == true)
            #expect(defaults.object(forKey: "followReduceMotion") as? Bool == true)
            #expect(defaults.object(forKey: "cleanTitles") as? Bool == false)
        }
    }

    @Test func loadsLiteralKeysIndependentlyOfSave() throws {
        try withDefaults { defaults, _ in
            defaults.set("B", forKey: "compactStyle")
            defaults.set(false, forKey: "peekOnFinished")
            defaults.set("mainDisplay", forKey: "displayPlacement")
            defaults.set(true, forKey: "launchAtLogin")
            defaults.set(false, forKey: "cleanTitles")
            let preferences = Preferences.load(from: defaults)
            #expect(preferences.compactStyle == .dots)
            #expect(!preferences.peekOnFinished)
            #expect(preferences.displayPlacement == .mainDisplay)
            #expect(preferences.launchAtLogin)
            #expect(preferences.followReduceMotion == false) // Missing key uses its default.
            #expect(!preferences.cleanTitles)
        }
    }

    @Test func unknownEnumValuesFallBackWithoutLosingRecognizedSettings() throws {
        try withDefaults { defaults, _ in
            defaults.set("future-style", forKey: "compactStyle")
            defaults.set("future-screen", forKey: "displayPlacement")
            defaults.set(false, forKey: "peekOnFinished")
            defaults.set(true, forKey: "launchAtLogin")
            let preferences = Preferences.load(from: defaults)
            #expect(preferences.compactStyle == .birdCount)
            #expect(preferences.displayPlacement == .builtInNotch)
            #expect(!preferences.peekOnFinished)
            #expect(preferences.launchAtLogin)
        }
    }

    @Test func unrecognizedTypesFallBackToDefaults() throws {
        try withDefaults { defaults, _ in
            defaults.set(42, forKey: "compactStyle")
            defaults.set(["enabled": true], forKey: "peekOnFinished")
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
            preferences.peekOnFinished = false
            preferences.save(to: defaults)
            Preferences().save(to: defaults)
            expectDefaults(Preferences.load(from: defaults))
        }
    }
}

extension PreferencesTests {
    @Test(arguments: [false, true])
    func peekOnFinishedRoundTrip(_ enabled: Bool) throws {
        try withDefaults { defaults, _ in
            var preferences = Preferences()
            preferences.peekOnFinished = enabled
            preferences.save(to: defaults)
            #expect(defaults.object(forKey: "peekOnFinished") as? Bool == enabled)
            #expect(Preferences.load(from: defaults) == preferences)
        }
    }

    @Test(arguments: [false, true], ["peek", "expand", "pulse"])
    func legacyAlertKeysAreIgnored(_ autoExpand: Bool, _ blocked: String) throws {
        try withDefaults { defaults, _ in
            defaults.set(autoExpand, forKey: "autoExpandOnBlocked")
            defaults.set(blocked, forKey: "blockedAlert")
            for finished in ["peek", "ear", "off"] {
                defaults.set(finished, forKey: "finishedAlert")
                expectDefaults(Preferences.load(from: defaults))
            }
            defaults.set(false, forKey: "peekOnFinished")
            var expected = Preferences()
            expected.peekOnFinished = false
            #expect(Preferences.load(from: defaults) == expected)
        }
    }
}

extension PreferencesTests {
    @Test(arguments: ["grouped", "heroAndRows", "rowsOnly"])
    func legacyListStyleIsIgnoredAndNotSaved(_ legacyStyle: String) throws {
        try withDefaults { defaults, _ in
            defaults.set(legacyStyle, forKey: "listStyle")
            defaults.set("B", forKey: "compactStyle")
            defaults.set(false, forKey: "peekOnFinished")
            var expected = Preferences()
            expected.compactStyle = .dots
            expected.peekOnFinished = false
            let loaded = Preferences.load(from: defaults)
            #expect(loaded == expected)
            try withDefaults { destination, name in
                loaded.save(to: destination)
                let persisted = try #require(destination.persistentDomain(forName: name))
                #expect(Set(persisted.keys) == ["compactStyle", "peekOnFinished", "displayPlacement", "launchAtLogin", "followReduceMotion", "cleanTitles"])
                #expect(persisted["listStyle"] == nil)
            }
        }
    }
}
