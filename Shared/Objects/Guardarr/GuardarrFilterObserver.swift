//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import Foundation
import GuardarrFilterKit
import JellyfinAPI

/// Applies a title's Guardarr filter list during playback.
///
/// One observer belongs to one `MediaPlayerItem`. It starts dark and muted, fetches the
/// title's list, and only then lets picture and sound through. If the list can't be
/// applied (no list, a replaced file, no server, a player that can't filter) the screen
/// stays dark, playback is held paused, and the reason is shown.
///
/// While a list is active, a 20 Hz tick reads the player's own position and applies the
/// mute, blackout and skip commands from `FilterController`.
@MainActor
final class GuardarrFilterObserver: ObservableObject, MediaPlayerObserver {

    enum Status: Equatable {
        case loading
        case active
        case unfiltered
        case blocked(String)
    }

    @Published
    private(set) var status: Status = .loading
    @Published
    private(set) var isBlackedOut = true

    weak var manager: MediaPlayerManager? {
        didSet {
            if let manager, manager !== oldValue {
                setup(with: manager)
            }
        }
    }

    private weak var item: MediaPlayerItem?
    private var controller: FilterController?
    private var clock = PlaybackClock()
    private var lastConfirmedMs: Int64?
    private var ticker: Timer?
    private var fetchTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    private static let tickInterval: TimeInterval = 0.05
    private static let playerCannotFilter = "This player can't apply filters. Choose VLC or Native as the player in Settings."

    init(item: MediaPlayerItem) {
        self.item = item
    }

    // MARK: lifecycle

    private func setup(with manager: MediaPlayerManager) {
        cancellables = []

        manager.$playbackItem
            .sink { [weak self] newItem in
                guard let self, let item = self.item, newItem !== item else { return }

                // Another item took over; its own observer filters it. Don't unmute here:
                // the next item's observer has already muted for its own load.
                self.teardown()
            }
            .store(in: &cancellables)

        manager.actions
            .sink { [weak self] action in
                switch action {
                case .stop, .error:
                    self?.teardown()
                default: ()
                }
            }
            .store(in: &cancellables)

        startTicker()
        fetchFilterList()
    }

    private func teardown() {
        ticker?.invalidate()
        ticker = nil
        fetchTask?.cancel()
        fetchTask = nil
        cancellables = []
    }

    private func startTicker() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        tick()
    }

    // MARK: fetch

    private func fetchFilterList() {
        guard let item else { return }

        let serverText = Defaults[.Guardarr.serverURL].trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = Defaults[.Guardarr.apiKey].trimmingCharacters(in: .whitespacesAndNewlines)
        let allowUnfiltered = Defaults[.Guardarr.allowUnfilteredTitles]
        let categories = Set(Defaults[.Guardarr.enabledCategories].compactMap(FilterCategory.init(rawValue:)))

        guard let server = URL(string: serverText), server.scheme != nil, !apiKey.isEmpty else {
            block(.notConfigured)
            return
        }
        guard let size = item.mediaSource.size.map({ Int64($0) }), size > 0 else {
            block(.unknownFileSize)
            return
        }
        guard let itemID = item.baseItem.id,
              let request = FilterRequest.make(server: server, itemID: itemID, fileSizeBytes: size, apiKey: apiKey)
        else {
            block(.failed("This title has no usable id."))
            return
        }

        fetchTask = Task { [weak self] in
            let result: FilterFetchResult
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                result = FilterFetchResult.from(status: status, body: data, requestedSizeBytes: size, requestedItemID: itemID)
            } catch {
                result = .failed(error.localizedDescription)
            }
            guard !Task.isCancelled, let self else { return }

            self.apply(FilterGate.decide(result, enabledCategories: categories, allowUnfilteredTitles: allowUnfiltered))
        }
    }

    private func apply(_ gate: FilterGate) {
        switch gate {
        case let .apply(timeline):
            controller = FilterController(timeline: timeline)
            status = .active
            manager?.logger.info("Guardarr filter active", metadata: ["ranges": .stringConvertible(timeline.muteRanges.count)])

        case .allowUnfiltered:
            status = .unfiltered

        case let .block(reason):
            block(reason)
        }
        tick()
    }

    private func block(_ reason: FilterBlockReason) {
        status = .blocked(reason.message)
        manager?.logger.warning("Guardarr filter blocked playback", metadata: ["reason": .string(reason.message)])
        tick()
    }

    // MARK: tick

    private func tick() {
        guard let manager, item != nil else {
            teardown()
            return
        }
        guard let player = manager.proxy as? MediaPlayerFilterable else {
            if manager.proxy != nil, status != .unfiltered {
                status = .blocked(Self.playerCannotFilter)
                manager.proxy?.pause()
            }
            isBlackedOut = status != .unfiltered
            return
        }

        // Picture in picture draws the video layer directly, outside the blackout cover.
        if status != .unfiltered, let pip = manager.proxy as? any MediaPlayerPictureInPictureCapable, pip.isPiPActive.value {
            output(player, muted: true, blackedOut: true)
            pip.stopPiP()
            manager.proxy?.pause()
            return
        }

        switch status {
        case .loading:
            output(player, muted: true, blackedOut: true)

        case .blocked:
            output(player, muted: true, blackedOut: true)
            if player.filterIsPlaying {
                manager.proxy?.pause()
            }

        case .unfiltered:
            output(player, muted: false, blackedOut: false)
            ticker?.invalidate()
            ticker = nil

        case .active:
            filter(player, manager: manager)
        }
    }

    private func filter(_ player: MediaPlayerFilterable, manager: MediaPlayerManager) {
        guard var controller, let position = player.filterPosition else {
            output(player, muted: true, blackedOut: true)
            return
        }

        let confirmedMs = position.milliseconds
        let now = ProcessInfo.processInfo.systemUptime

        if confirmedMs != lastConfirmedMs {
            // The viewer seeked back: a skip range they return to must be skipped again.
            if let lastConfirmedMs, confirmedMs < lastConfirmedMs - 1000 {
                controller.viewerDidSeek()
            }
            clock.record(positionMs: confirmedMs, at: now, rate: player.filterRate, isPlaying: player.filterIsPlaying)
            lastConfirmedMs = confirmedMs
        }

        let estimatedMs = max(confirmedMs, clock.estimate(at: now) ?? confirmedMs)
        let command = controller.update(
            confirmedMs: confirmedMs,
            estimatedMs: estimatedMs,
            rate: player.filterRate,
            audioOffsetMs: manager.audioOffset.milliseconds
        )
        self.controller = controller

        output(player, muted: command.muted, blackedOut: command.blackedOut)

        if let seekMs = command.seekToMs {
            let target = Duration.milliseconds(seekMs)
            manager.seconds = target
            manager.proxy?.setSeconds(target)
        }
    }

    private func output(_ player: MediaPlayerFilterable, muted: Bool, blackedOut: Bool) {
        // Checked against the player every tick: a track switch or a new audio output
        // can reset mute behind the filter's back.
        if player.filterIsMuted != muted {
            player.setFilterMuted(muted)
        }
        if isBlackedOut != blackedOut {
            isBlackedOut = blackedOut
        }
    }
}

extension MediaPlayerItem {

    var guardarrFilter: GuardarrFilterObserver? {
        observers.lazy.compactMap { $0 as? GuardarrFilterObserver }.first
    }

    /// Attaches a Guardarr filter when filtering is on for the current user. Called as
    /// the player receives each item, before playback starts, so the filter's first
    /// state (dark and muted) is in place before any frame.
    func attachGuardarrFilterIfEnabled(manager: MediaPlayerManager) {
        guard Defaults[.Guardarr.isEnabled], guardarrFilter == nil else { return }

        let observer = GuardarrFilterObserver(item: self)
        observers.append(observer)
        observer.manager = manager
    }
}

private extension Duration {

    var milliseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1000 + attoseconds / 1_000_000_000_000_000
    }
}
