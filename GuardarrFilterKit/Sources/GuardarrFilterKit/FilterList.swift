//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// What the player does during a filter range.
///
/// Unknown actions from a newer server decode as `.blackout`, the strictest
/// action this client can perform, so an old client never filters less than asked.
public enum FilterAction: String, Sendable, Equatable {

    case mute
    case blackout
    case skip

    init(serverValue: String) {
        self = FilterAction(rawValue: serverValue) ?? .blackout
    }
}

/// The kind of content a range covers. Unknown categories decode as `.other`,
/// which can't be switched off, so a new category is never silently ignored.
public enum FilterCategory: String, Sendable, Equatable, CaseIterable {

    case language
    case nudity
    case sexual
    case violence
    case gore
    case other

    init(serverValue: String) {
        self = FilterCategory(rawValue: serverValue) ?? .other
    }
}

/// How strong a language or nudity event is, so the viewer can pick a level.
///
/// Language is `mild`, `moderate` or `strong`; nudity is `partial` (bare buttocks) or
/// `full` (bare breasts or genitals).
public enum FilterSeverity: String, Sendable, Equatable, Codable, CaseIterable {

    case mild
    case moderate
    case strong
    case partial
    case full

    /// A severity from the server. A value this client doesn't know, or one that doesn't
    /// belong to the category, reads as missing, which is filtered at every level, so a
    /// newer server's list is never under-filtered. Categories without severities have none.
    init?(serverValue: String?, category: FilterCategory) {
        let valid: [FilterSeverity]
        switch category {
        case .language:
            valid = [.mild, .moderate, .strong]

        case .nudity:
            valid = [.partial, .full]

        default:
            return nil
        }
        guard let serverValue, let severity = FilterSeverity(rawValue: serverValue), valid.contains(severity) else {
            return nil
        }

        self = severity
    }
}

public struct FilterEvent: Sendable, Equatable {

    public let action: FilterAction
    public let category: FilterCategory
    public let startMs: Int64
    public let endMs: Int64
    public let label: String?
    /// `nil` when the server didn't say, which counts as matching every level.
    public let severity: FilterSeverity?

    public init(
        action: FilterAction,
        category: FilterCategory,
        startMs: Int64,
        endMs: Int64,
        label: String? = nil,
        severity: FilterSeverity? = nil
    ) {
        self.action = action
        self.category = category
        self.startMs = startMs
        self.endMs = endMs
        self.label = label
        self.severity = severity
    }
}

/// A title's filter list, as served by `GET /api/v1/items/{itemId}/filters`.
/// See docs/filter-list-v1.md in the Guardarr repository.
public struct FilterList: Sendable, Equatable {

    public let schema: Int
    public let itemID: String
    public let revision: Int
    public let fileSizeBytes: Int64
    public let events: [FilterEvent]
    /// Categories the file was actually scanned for. Unknown values from a newer
    /// server are dropped: an unknown category can't vouch for anything this app filters.
    public let coverage: Set<FilterCategory>
}

extension FilterList: Decodable {

    private enum CodingKeys: String, CodingKey {
        case schema
        case itemId
        case revision
        case file
        case events
        case coverage
    }

    private struct File: Decodable {
        let sizeBytes: Int64
    }

    private struct Event: Decodable {
        let action: String
        let category: String
        let startMs: Int64
        let endMs: Int64
        let label: String?
        let severity: String?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(Int.self, forKey: .schema)
        itemID = try container.decode(String.self, forKey: .itemId)
        revision = try container.decode(Int.self, forKey: .revision)
        fileSizeBytes = try container.decode(File.self, forKey: .file).sizeBytes
        coverage = try Set((container.decodeIfPresent([String].self, forKey: .coverage) ?? []).compactMap(FilterCategory.init(rawValue:)))
        events = try container.decode([Event].self, forKey: .events).map { event in
            guard event.endMs > event.startMs, event.startMs >= 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .events,
                    in: container,
                    debugDescription: "filter range \(event.startMs)-\(event.endMs) is empty or negative"
                )
            }

            let category = FilterCategory(serverValue: event.category)
            return FilterEvent(
                action: FilterAction(serverValue: event.action),
                category: category,
                startMs: event.startMs,
                endMs: event.endMs,
                label: event.label,
                severity: FilterSeverity(serverValue: event.severity, category: category)
            )
        }
    }
}
