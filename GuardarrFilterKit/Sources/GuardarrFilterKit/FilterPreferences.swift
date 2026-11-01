//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// What the player does for a language event. Only muting exists today.
public enum LanguageAction: String, Sendable, Equatable, Codable, CaseIterable {

    case mute
    // A future `bleep` goes here. Add it to `playerAction` so the player can honor it.

    /// The action the player performs for a language event.
    var playerAction: FilterAction {
        switch self {
        case .mute: .mute
        }
    }
}

/// What the player does for a nudity event.
public enum NudityAction: String, Sendable, Equatable, Codable, CaseIterable {

    case skip
    case blackout

    var playerAction: FilterAction {
        switch self {
        case .skip: .skip
        case .blackout: .blackout
        }
    }
}

/// What one viewer chooses to filter.
///
/// The server publishes everything it finds, with a severity. These preferences decide
/// which of those events the player acts on. `.other` is never switched off.
public struct FilterPreferences: Sendable, Equatable {

    /// Categories the viewer filters. A category the title wasn't scanned for blocks playback.
    public var categories: Set<FilterCategory>

    /// Language levels to mute. Defaults to moderate and strong.
    public var mutedSeverities: Set<FilterSeverity>
    /// Words the viewer allows. An event is left alone when every word in its label is allowed.
    public var allowedWords: Set<String>
    /// Words the viewer always wants muted, whatever their level.
    public var blockedWords: Set<String>
    public var languageAction: LanguageAction

    /// Whether bare buttocks count. Bare breasts and genitals always do.
    public var includePartialNudity: Bool
    public var nudityAction: NudityAction

    public init(
        categories: Set<FilterCategory> = [.language, .nudity],
        mutedSeverities: Set<FilterSeverity> = [.moderate, .strong],
        allowedWords: Set<String> = [],
        blockedWords: Set<String> = [],
        languageAction: LanguageAction = .mute,
        includePartialNudity: Bool = true,
        nudityAction: NudityAction = .skip
    ) {
        self.categories = categories
        self.mutedSeverities = mutedSeverities.intersection([.mild, .moderate, .strong])
        self.allowedWords = Set(allowedWords.map(Self.normalize))
        self.blockedWords = Set(blockedWords.map(Self.normalize))
        self.languageAction = languageAction
        self.includePartialNudity = includePartialNudity
        self.nudityAction = nudityAction
    }

    /// The preferences for a viewer whose only saved choice is the original category list.
    ///
    /// Before language levels existed, every language word was muted. A viewer who had
    /// language on keeps that, with all three levels; everyone else gets the defaults.
    public static func upgrading(fromEnabledCategories legacy: [String]?) -> FilterPreferences {
        guard let legacy, legacy.contains(FilterCategory.language.rawValue) else { return FilterPreferences() }

        return FilterPreferences(mutedSeverities: [.mild, .moderate, .strong])
    }

    /// Lowercased and trimmed, so the viewer's words match the server's labels.
    public static func normalize(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The words in an event label, normalized.
    static func words(in label: String?) -> [String] {
        guard let label else { return [] }

        let separators = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted
        return label.lowercased().components(separatedBy: separators).filter { !$0.isEmpty }
    }

    /// The categories checked against a file's coverage. `.other` is filtered without being scanned for.
    public var filteredCategories: Set<FilterCategory> {
        categories.subtracting([.other])
    }

    /// The action the player takes for `event` and whether it applies at all.
    func resolve(_ event: FilterEvent) -> FilterAction? {
        switch event.category {
        case .other:
            return event.action

        case .language:
            guard categories.contains(.language), mutesLanguage(event) else { return nil }

            // A server action stronger than muting is kept.
            return event.action == .mute ? languageAction.playerAction : event.action

        case .nudity:
            guard categories.contains(.nudity), includePartialNudity || event.severity != .partial else { return nil }

            return nudityAction.playerAction

        default:
            return categories.contains(event.category) ? event.action : nil
        }
    }

    private func mutesLanguage(_ event: FilterEvent) -> Bool {
        let words = Self.words(in: event.label)
        if words.contains(where: blockedWords.contains) {
            return true
        }
        // A missing severity matches every level.
        if let severity = event.severity, !mutedSeverities.contains(severity) {
            return false
        }
        // Allowed words only opt out when nothing else in the label is a word to mute.
        return words.isEmpty || !words.allSatisfy(allowedWords.contains)
    }
}

extension FilterPreferences: Codable {

    private enum CodingKeys: String, CodingKey {
        case categories
        case mutedSeverities
        case allowedWords
        case blockedWords
        case languageAction
        case includePartialNudity
        case nudityAction
    }

    /// Missing or unknown fields fall back to the defaults, so older saved preferences keep loading.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = FilterPreferences()
        self.init(
            categories: Set(
                (try? container.decode([String].self, forKey: .categories))?.compactMap(FilterCategory.init(rawValue:))
                    ?? Array(defaults.categories)
            ),
            mutedSeverities: Set(
                (try? container.decode([String].self, forKey: .mutedSeverities))?.compactMap(FilterSeverity.init(rawValue:))
                    ?? Array(defaults.mutedSeverities)
            ),
            allowedWords: (try? container.decode(Set<String>.self, forKey: .allowedWords)) ?? [],
            blockedWords: (try? container.decode(Set<String>.self, forKey: .blockedWords)) ?? [],
            languageAction: (try? container.decode(LanguageAction.self, forKey: .languageAction)) ?? defaults.languageAction,
            includePartialNudity: (try? container.decode(Bool.self, forKey: .includePartialNudity)) ?? defaults.includePartialNudity,
            nudityAction: (try? container.decode(NudityAction.self, forKey: .nudityAction)) ?? defaults.nudityAction
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(categories.map(\.rawValue).sorted(), forKey: .categories)
        try container.encode(mutedSeverities.map(\.rawValue).sorted(), forKey: .mutedSeverities)
        try container.encode(allowedWords.sorted(), forKey: .allowedWords)
        try container.encode(blockedWords.sorted(), forKey: .blockedWords)
        try container.encode(languageAction, forKey: .languageAction)
        try container.encode(includePartialNudity, forKey: .includePartialNudity)
        try container.encode(nudityAction, forKey: .nudityAction)
    }
}
