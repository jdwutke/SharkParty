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

    case notFiltered(ScanStatus?)
    case fileChanged(ScanStatus?)
    case notFullyScanned(Set<FilterCategory>)
    case unknownFileSize
    case notConfigured
    case unauthorized
    case failed(String)

    public var message: String {
        switch self {
        case let .notFiltered(scan):
            scan.map(\.progressText) ?? "This title hasn't been filtered yet."

        case let .fileChanged(scan):
            "This title's file was replaced after it was filtered, so its filter is out of date."
                + (scan.map { " \($0.progressText)" } ?? "")

        case let .notFullyScanned(missing):
            "This title hasn't been checked for "
                + missing.map(\.rawValue).sorted().joined(separator: " or ")
                + " yet. Turn those categories off in Settings to watch it now."

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
            // A category the viewer filters that the file was never scanned for
            // would play through unfiltered, so it blocks like a missing list.
            let missing = enabledCategories.subtracting(list.coverage).subtracting([.other])
            guard missing.isEmpty else { return .block(.notFullyScanned(missing)) }

            return .apply(FilterTimeline(events: list.events, enabledCategories: enabledCategories))

        case let .notFiltered(scan):
            return allowUnfilteredTitles ? .allowUnfiltered : .block(.notFiltered(scan))

        case let .fileChanged(scan):
            return .block(.fileChanged(scan))

        case .unauthorized:
            return .block(.unauthorized)

        case let .failed(detail):
            return .block(.failed(detail))
        }
    }

    /// Whether this outcome should ask the server for a scan: no list or a stale
    /// one, and no scan already waiting or running.
    public static func shouldRequestScan(_ result: FilterFetchResult) -> Bool {
        switch result {
        case let .notFiltered(scan), let .fileChanged(scan):
            !(scan?.isActive ?? false)
        default:
            false
        }
    }

    /// Whether to keep checking back: a scan is queued or running.
    public static func isWaitingForScan(_ result: FilterFetchResult) -> Bool {
        switch result {
        case let .notFiltered(scan), let .fileChanged(scan):
            scan?.isActive ?? false
        default:
            false
        }
    }
}
