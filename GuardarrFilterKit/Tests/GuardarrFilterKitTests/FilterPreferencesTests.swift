//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
@testable import GuardarrFilterKit
import Testing

private func word(_ label: String?, _ severity: FilterSeverity?, at start: Int64 = 1000) -> FilterEvent {
    FilterEvent(action: .mute, category: .language, startMs: start, endMs: start + 100, label: label, severity: severity)
}

private func nudity(_ severity: FilterSeverity?, action: FilterAction = .skip, at start: Int64 = 5000) -> FilterEvent {
    FilterEvent(action: action, category: .nudity, startMs: start, endMs: start + 1000, severity: severity)
}

private func state(_ events: [FilterEvent], _ preferences: FilterPreferences, at position: Int64) -> FilterState {
    FilterTimeline(events: events, preferences: preferences).state(from: position, through: position)
}

struct LanguagePreferenceTests {

    @Test
    func `default preferences mute strong and moderate but not mild`() {
        let prefs = FilterPreferences()
        #expect(state([word("fuck", .strong)], prefs, at: 1050).muted)
        #expect(state([word("shit", .moderate)], prefs, at: 1050).muted)
        #expect(state([word("damn", .mild)], prefs, at: 1050) == .clear)
    }

    @Test
    func `turning mild on mutes mild words`() {
        let prefs = FilterPreferences(mutedSeverities: [.mild, .moderate, .strong])
        #expect(state([word("damn", .mild)], prefs, at: 1050).muted)
    }

    @Test
    func `a missing severity is filtered whenever language is on`() {
        #expect(state([word("damn", nil)], FilterPreferences(mutedSeverities: []), at: 1050).muted)
        #expect(state([word("damn", nil)], FilterPreferences(categories: [.nudity]), at: 1050) == .clear)
    }

    @Test
    func `an unknown or mismatched severity reads as missing`() {
        #expect(FilterSeverity(serverValue: "extreme", category: .language) == nil)
        #expect(FilterSeverity(serverValue: "full", category: .language) == nil)
        #expect(FilterSeverity(serverValue: "mild", category: .language) == .mild)
        #expect(FilterSeverity(serverValue: nil, category: .language) == nil)
    }

    @Test
    func `an unknown severity is muted even with strong off and mild on`() {
        let prefs = FilterPreferences(mutedSeverities: [.mild])
        let unknown = word("damn", FilterSeverity(serverValue: "extreme", category: .language))
        #expect(state([unknown], prefs, at: 1050).muted)
        #expect(state([word("damn", .strong)], prefs, at: 1050) == .clear)
    }

    @Test
    func `upgrading a viewer who had language on mutes every level`() {
        #expect(FilterPreferences.upgrading(fromEnabledCategories: ["language"]).mutedSeverities == [.mild, .moderate, .strong])
        #expect(FilterPreferences.upgrading(fromEnabledCategories: ["nudity"]) == FilterPreferences())
        #expect(FilterPreferences.upgrading(fromEnabledCategories: nil) == FilterPreferences())
    }

    @Test
    func `an allowed word is not muted`() {
        let prefs = FilterPreferences(mutedSeverities: [.mild, .moderate, .strong], allowedWords: ["Hell"])
        #expect(state([word("hell", .mild)], prefs, at: 1050) == .clear)
        #expect(state([word("damn", .mild)], prefs, at: 1050).muted)
    }

    @Test
    func `an allowed word is muted when the same event has another muted word`() {
        let prefs = FilterPreferences(allowedWords: ["hell"])
        #expect(state([word("hell shit", .moderate)], prefs, at: 1050).muted)
        #expect(state([word("hell", .moderate)], prefs, at: 1050) == .clear)
    }

    @Test
    func `a blocked word is muted even at a level the viewer left off`() {
        let prefs = FilterPreferences(mutedSeverities: [.strong], blockedWords: ["damn"])
        #expect(state([word("damn", .mild)], prefs, at: 1050).muted)
        #expect(state([word("hell", .mild)], prefs, at: 1050) == .clear)
    }

    @Test
    func `a blocked word beats an allowed one`() {
        let prefs = FilterPreferences(allowedWords: ["damn"], blockedWords: ["damn"])
        #expect(state([word("damn", .mild)], prefs, at: 1050).muted)
    }

    @Test
    func `words are split out of a label`() {
        #expect(FilterPreferences.words(in: "Son-of-a-BITCH!") == ["son", "of", "a", "bitch"])
        #expect(FilterPreferences.words(in: nil).isEmpty)
    }

    @Test
    func `language off drops language events`() {
        #expect(state([word("fuck", .strong)], FilterPreferences(categories: [.nudity]), at: 1050) == .clear)
    }

    @Test
    func `a stronger server action is kept for language`() {
        let blackout = FilterEvent(action: .blackout, category: .language, startMs: 0, endMs: 10, severity: .strong)
        #expect(state([blackout], FilterPreferences(), at: 5).blackedOut)
    }
}

struct NudityPreferenceTests {

    @Test
    func `partial off still skips full nudity`() {
        let prefs = FilterPreferences(includePartialNudity: false)
        #expect(state([nudity(.partial)], prefs, at: 5500) == .clear)
        #expect(state([nudity(.full)], prefs, at: 5500).skipTo == 6000)
    }

    @Test
    func `partial on skips both`() {
        let prefs = FilterPreferences()
        #expect(state([nudity(.partial)], prefs, at: 5500).skipTo == 6000)
        #expect(state([nudity(.full)], prefs, at: 5500).skipTo == 6000)
    }

    @Test
    func `unknown or missing nudity severity is filtered even with partial off`() {
        let prefs = FilterPreferences(includePartialNudity: false)
        #expect(FilterSeverity(serverValue: "graphic", category: .nudity) == nil)
        #expect(state([nudity(FilterSeverity(serverValue: "graphic", category: .nudity))], prefs, at: 5500).skipTo == 6000)
        #expect(state([nudity(nil)], prefs, at: 5500).skipTo == 6000)
    }

    @Test
    func `the viewer's action replaces the server's`() {
        let prefs = FilterPreferences(nudityAction: .blackout)
        let result = state([nudity(.full, action: .skip)], prefs, at: 5500)
        #expect(result == FilterState(muted: true, blackedOut: true, skipTo: nil, skipFrom: nil))
        #expect(state([nudity(.full, action: .blackout)], FilterPreferences(), at: 5500).skipTo == 6000)
    }

    @Test
    func `nudity off drops nudity events`() {
        #expect(state([nudity(.full)], FilterPreferences(categories: [.language]), at: 5500) == .clear)
    }

    @Test
    func `other is always filtered`() {
        let other = FilterEvent(action: .blackout, category: .other, startMs: 0, endMs: 10)
        #expect(state([other], FilterPreferences(categories: []), at: 5).blackedOut)
    }
}

struct PreferencesGateAndCodingTests {

    private func list(coverage: Set<FilterCategory>) -> FilterList {
        let body = Data("""
        {"schema":1,"itemId":"a","revision":1,"file":{"sizeBytes":1},
         "coverage":[\(coverage.map { "\"\($0.rawValue)\"" }.joined(separator: ","))],
         "events":[{"action":"mute","category":"language","startMs":1,"endMs":2,"label":"damn","severity":"mild"},
                   {"action":"skip","category":"nudity","startMs":5,"endMs":9,"severity":"weird"}]}
        """.utf8)
        guard case let .filtered(list) = FilterFetchResult.from(status: 200, body: body, requestedSizeBytes: 1) else {
            preconditionFailure("list should decode")
        }

        return list
    }

    @Test
    func `severity decodes, and an unknown nudity level reads as missing`() {
        let events = list(coverage: [.language, .nudity]).events
        #expect(events[0].severity == .mild)
        #expect(events[1].severity == nil)
    }

    @Test
    func `a filtered category missing from coverage blocks playback`() {
        let result = FilterFetchResult.filtered(list(coverage: [.language]))
        #expect(FilterGate.decide(result, preferences: FilterPreferences(), allowUnfilteredTitles: true)
            == .block(.notFullyScanned([.nudity])))
        let noNudity = FilterPreferences(categories: [.language])
        if case .apply = FilterGate.decide(result, preferences: noNudity, allowUnfilteredTitles: false) {} else {
            Issue.record("a category the viewer turned off must not block")
        }
    }

    @Test
    func `preferences survive encoding and tolerate missing fields`() throws {
        let prefs = FilterPreferences(
            categories: [.language],
            mutedSeverities: [.strong],
            allowedWords: ["Hell"],
            blockedWords: ["damn"],
            includePartialNudity: false,
            nudityAction: .blackout
        )
        let decoded = try JSONDecoder().decode(FilterPreferences.self, from: JSONEncoder().encode(prefs))
        #expect(decoded == prefs)
        #expect(decoded.allowedWords == ["hell"])
        #expect(try JSONDecoder().decode(FilterPreferences.self, from: Data("{}".utf8)) == FilterPreferences())
        #expect(try JSONDecoder().decode(FilterPreferences.self, from: Data(#"{"nudityAction":"zap"}"#.utf8)) == FilterPreferences())
    }
}
