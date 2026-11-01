//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AVFoundation
import Foundation

extension AVMediaPlayerProxy: MediaPlayerFilterable {

    var filterPosition: Duration? {
        let time = player.currentTime()
        guard time.isNumeric else { return nil }

        return .seconds(time.seconds)
    }

    var filterIsPlaying: Bool {
        player.timeControlStatus == .playing
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
