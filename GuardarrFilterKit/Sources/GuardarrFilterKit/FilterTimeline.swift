//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// A half-open range of milliseconds, `[start, end)`.
public struct FilterRange: Sendable, Equatable {

    public let start: Int64
    public let end: Int64

    public init(start: Int64, end: Int64) {
        self.start = start
        self.end = end
    }

    func intersects(_ low: Int64, _ high: Int64) -> Bool {
        start <= high && end > low
    }
}

/// What the player should be doing over a window of playback.
public struct FilterState: Sendable, Equatable {

    public var muted: Bool
    public var blackedOut: Bool
    /// Where to seek to leave a skip range, if the window touches one.
    public var skipTo: Int64?
    /// Where that skip range starts.
    public var skipFrom: Int64?

    public static let clear = FilterState(muted: false, blackedOut: false, skipTo: nil, skipFrom: nil)
}

/// A title's filter list compiled for playback.
///
/// Each action is flattened into sorted, non-overlapping ranges. A skip also blacks out
/// and mutes, so nothing shows while the seek lands. A blackout also mutes. Overlapping
/// or touching skips chain, so one seek clears them all.
public struct FilterTimeline: Sendable, Equatable {

    public let muteRanges: [FilterRange]
    public let blackoutRanges: [FilterRange]
    public let skipRanges: [FilterRange]

    /// - Parameter enabledCategories: categories the viewer filters. `.other` is always
    ///   filtered, because unknown categories from a newer server decode as `.other`.
    public init(events: [FilterEvent], enabledCategories: Set<FilterCategory>) {
        let active = events.filter { enabledCategories.contains($0.category) || $0.category == .other }

        func ranges(_ actions: Set<FilterAction>) -> [FilterRange] {
            Self.merge(active.filter { actions.contains($0.action) }.map { FilterRange(start: $0.startMs, end: $0.endMs) })
        }

        muteRanges = ranges([.mute, .blackout, .skip])
        blackoutRanges = ranges([.blackout, .skip])
        skipRanges = ranges([.skip])
    }

    public var isEmpty: Bool {
        muteRanges.isEmpty
    }

    /// The state for the playback window `[low, high]`. A range anywhere in the window
    /// counts, so a word shorter than the gap between two position samples is still caught.
    public func state(from low: Int64, through high: Int64) -> FilterState {
        let low = min(low, high)
        var state = FilterState.clear
        state.muted = Self.firstIntersecting(muteRanges, low, high) != nil
        state.blackedOut = Self.firstIntersecting(blackoutRanges, low, high) != nil
        if let skip = Self.firstIntersecting(skipRanges, low, high) {
            state.skipTo = skipRanges[skip].end
            state.skipFrom = skipRanges[skip].start
        }
        return state
    }

    /// Sorted, with overlapping or touching ranges joined.
    static func merge(_ ranges: [FilterRange]) -> [FilterRange] {
        var merged: [FilterRange] = []
        for range in ranges.sorted(by: { ($0.start, $0.end) < ($1.start, $1.end) }) {
            if let last = merged.last, range.start <= last.end {
                merged[merged.count - 1] = FilterRange(start: last.start, end: max(last.end, range.end))
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// Index of the first range that intersects `[low, high]`. Ranges are sorted and
    /// disjoint, so this is a binary search for the first range ending after `low`.
    static func firstIntersecting(_ ranges: [FilterRange], _ low: Int64, _ high: Int64) -> Int? {
        var lo = 0
        var hi = ranges.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if ranges[mid].end > low {
                hi = mid
            } else {
                lo = mid + 1
            }
        }
        guard lo < ranges.count, ranges[lo].intersects(low, high) else { return nil }

        return lo
    }
}
