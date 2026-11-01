//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Estimates the playback position between the player's own position updates.
///
/// Some players (VLC) report position only a few times a second. Between reports the
/// position is extrapolated from the last report and the playback rate, for at most
/// `maxExtrapolation` seconds, so a stalled player isn't assumed to keep moving.
public struct PlaybackClock: Sendable {

    public var maxExtrapolation: TimeInterval = 1

    private var sampleMs: Int64?
    private var sampleTime: TimeInterval = 0
    private var rate: Double = 1
    private var isPlaying = false

    public init() {}

    /// - Parameter time: a monotonic timestamp in seconds, such as `ProcessInfo.systemUptime`.
    public mutating func record(positionMs: Int64, at time: TimeInterval, rate: Double, isPlaying: Bool) {
        sampleMs = positionMs
        sampleTime = time
        self.rate = rate
        self.isPlaying = isPlaying
    }

    /// The last reported position.
    public var reportedMs: Int64? {
        sampleMs
    }

    public func estimate(at time: TimeInterval) -> Int64? {
        guard let sampleMs else { return nil }
        guard isPlaying, rate > 0 else { return sampleMs }

        let elapsed = min(max(0, time - sampleTime), maxExtrapolation)
        return sampleMs + Int64((elapsed * rate * 1000).rounded())
    }
}

/// What the player must do right now.
public struct FilterCommand: Sendable, Equatable {

    public var muted: Bool
    public var blackedOut: Bool
    public var seekToMs: Int64?
}

/// Turns playback positions into mute, blackout and seek commands.
///
/// Each update looks at the window from the last position the player confirmed to the
/// estimated position plus a lead. Filtering therefore starts slightly early and ends
/// only once the player has confirmed it is past a range, never late.
///
/// A seek out of a skip range is issued once and then treated as in flight: the screen
/// stays black and muted until the player has played at least `settleMs` past the
/// target. Some players report the target position as soon as a seek is requested,
/// before it lands, so a position at the target is not proof the seek is done. If the
/// player lands short (on an earlier keyframe), it plays out the rest of the range dark.
public struct FilterController: Sendable {

    public let timeline: FilterTimeline
    public var leadMs: Int64
    public var settleMs: Int64

    private var issuedSeekTarget: Int64?
    private var seekInFlight: (from: Int64, to: Int64)?

    /// How far before a pending skip range a position must be to count as the viewer
    /// moving elsewhere, rather than a late report from before the seek.
    private static let staleReportWindowMs: Int64 = 2000

    public init(timeline: FilterTimeline, leadMs: Int64 = 150, settleMs: Int64 = 250) {
        self.timeline = timeline
        self.leadMs = leadMs
        self.settleMs = settleMs
    }

    public var isSeekInFlight: Bool {
        seekInFlight != nil
    }

    /// - Parameters:
    ///   - confirmedMs: the last position the player itself reported.
    ///   - estimatedMs: the best estimate of the current position, at least `confirmedMs`
    ///     while playing.
    ///   - rate: the playback rate. The lead scales with it.
    ///   - audioOffsetMs: the viewer's audio delay. Positive means sound plays later than
    ///     the picture, so mutes are held that much longer; negative means sooner, so
    ///     they start that much earlier.
    public mutating func update(
        confirmedMs: Int64,
        estimatedMs: Int64,
        rate: Double = 1,
        audioOffsetMs: Int64 = 0
    ) -> FilterCommand {
        let low = min(confirmedMs, estimatedMs)
        let lead = Int64((Double(leadMs) * max(1, rate)).rounded())
        let high = max(confirmedMs, estimatedMs) + lead

        if let pending = seekInFlight {
            let landed = confirmedMs >= pending.to + settleMs
            let movedElsewhere = confirmedMs < pending.from - Self.staleReportWindowMs
            if landed || movedElsewhere {
                seekInFlight = nil
            } else {
                return FilterCommand(muted: true, blackedOut: true, seekToMs: nil)
            }
        }

        let skipState = timeline.state(from: low, through: high)
        let filterState = timeline.state(
            from: low - max(0, audioOffsetMs),
            through: high + max(0, -audioOffsetMs)
        )

        var seek: Int64?
        if let target = skipState.skipTo, target > low {
            if issuedSeekTarget != target {
                issuedSeekTarget = target
                seekInFlight = (from: skipState.skipFrom ?? low, to: target)
                seek = target
            }
        } else {
            issuedSeekTarget = nil
        }

        return FilterCommand(
            muted: filterState.muted || seek != nil,
            blackedOut: filterState.blackedOut || seek != nil,
            seekToMs: seek
        )
    }

    /// Call after the viewer seeks, so a skip range they seek back into is skipped again.
    /// Ignored while a filter seek is in flight: late position reports from before that
    /// seek look like a viewer seek and must not re-issue it.
    public mutating func viewerDidSeek() {
        guard seekInFlight == nil else { return }

        issuedSeekTarget = nil
    }
}
