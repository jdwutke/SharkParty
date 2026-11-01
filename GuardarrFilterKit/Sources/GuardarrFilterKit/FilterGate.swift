//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Why filtered playback can't go ahead. `message` is shown to the viewer.
public enum FilterBlockReason: Sendable, Equatable {

    case notFiltered
    case fileChanged
    case unknownFileSize
    case notConfigured
    case unauthorized
    case failed(String)

    public var message: String {
        switch self {
        case .notFiltered:
            "This title hasn't been filtered yet."
        case .fileChanged:
            "This title's file was replaced after it was filtered, so its filter is out of date."
        case .unknownFileSize:
            "The server didn't report this file's size, so its filter can't be matched to it."
        case .notConfigured:
            "Filtering is on, but no filter server is set up in Settings."
        case .unauthorized:
            "The filter server rejected this app's key."
        case let .failed(detail):
            "The filter couldn't be loaded. \(detail)"
        }
    }
}

/// Whether playback may start, decided once per title before the first frame.
///
/// With filtering on, every outcome other than a matching filter list blocks playback.
/// The one exception is a title that simply has no list yet, and only when the
/// profile allows unfiltered titles. A list for a replaced file is never applied.
public enum FilterGate: Sendable, Equatable {

    case apply(FilterTimeline)
    case allowUnfiltered
    case block(FilterBlockReason)

    public static func decide(
        _ result: FilterFetchResult,
        enabledCategories: Set<FilterCategory>,
        allowUnfilteredTitles: Bool
    ) -> FilterGate {
        switch result {
        case let .filtered(list):
            .apply(FilterTimeline(events: list.events, enabledCategories: enabledCategories))
        case .notFiltered:
            allowUnfilteredTitles ? .allowUnfiltered : .block(.notFiltered)
        case .fileChanged:
            .block(.fileChanged)
        case .unauthorized:
            .block(.unauthorized)
        case let .failed(detail):
            .block(.failed(detail))
        }
    }
}
