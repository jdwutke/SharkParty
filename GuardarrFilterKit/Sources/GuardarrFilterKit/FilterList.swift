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

public struct FilterEvent: Sendable, Equatable {

    public let action: FilterAction
    public let category: FilterCategory
    public let startMs: Int64
    public let endMs: Int64
    public let label: String?

    public init(action: FilterAction, category: FilterCategory, startMs: Int64, endMs: Int64, label: String? = nil) {
        self.action = action
        self.category = category
        self.startMs = startMs
        self.endMs = endMs
        self.label = label
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
}

extension FilterList: Decodable {

    private enum CodingKeys: String, CodingKey {
        case schema
        case itemId
        case revision
        case file
        case events
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
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(Int.self, forKey: .schema)
        itemID = try container.decode(String.self, forKey: .itemId)
        revision = try container.decode(Int.self, forKey: .revision)
        fileSizeBytes = try container.decode(File.self, forKey: .file).sizeBytes
        events = try container.decode([Event].self, forKey: .events).map { event in
            guard event.endMs > event.startMs, event.startMs >= 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .events,
                    in: container,
                    debugDescription: "filter range \(event.startMs)-\(event.endMs) is empty or negative"
                )
            }

            return FilterEvent(
                action: FilterAction(serverValue: event.action),
                category: FilterCategory(serverValue: event.category),
                startMs: event.startMs,
                endMs: event.endMs,
                label: event.label
            )
        }
    }
}
