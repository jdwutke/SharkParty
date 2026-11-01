//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// A player that Guardarr filtering can drive.
///
/// The filter reads the position many times a second, so `filterPosition` must come
/// straight from the player, not from `MediaPlayerManager.seconds`, which some players
/// update only once a second.
@MainActor
protocol MediaPlayerFilterable {

    /// The player's own current position, or `nil` before it has one.
    var filterPosition: Duration? { get }
    var filterIsPlaying: Bool { get }
    var filterRate: Double { get }
    var filterIsMuted: Bool { get }

    func setFilterMuted(_ muted: Bool)
}
