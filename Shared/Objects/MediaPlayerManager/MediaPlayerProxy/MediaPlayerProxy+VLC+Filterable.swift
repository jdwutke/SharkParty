//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftVLC

extension VLCMediaPlayerProxy: MediaPlayerFilterable {

    /// libVLC reports time a few times a second. The filter extrapolates between reports.
    var filterPosition: Duration? {
        switch player.state {
        case .playing, .paused:
            player.currentTime
        default:
            nil
        }
    }

    var filterIsPlaying: Bool {
        player.state == .playing
    }

    var filterRate: Double {
        Double(player.rate)
    }

    var filterIsMuted: Bool {
        player.isMuted
    }

    func setFilterMuted(_ muted: Bool) {
        player.isMuted = muted
    }
}
