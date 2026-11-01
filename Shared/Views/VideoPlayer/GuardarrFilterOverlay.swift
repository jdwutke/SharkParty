//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// Covers the video while Guardarr filtering says it must not be seen: during blackout
/// and skip ranges, while the filter list loads, and when filtered playback is blocked.
/// It sits above the video and its subtitles, and below the playback controls.
struct GuardarrFilterOverlay: View {

    @ObservedObject
    var manager: MediaPlayerManager

    var body: some View {
        if let observer = manager.playbackItem?.guardarrFilter {
            Content(observer: observer)
        }
    }

    private struct Content: View {

        @ObservedObject
        var observer: GuardarrFilterObserver

        var body: some View {
            ZStack {
                if observer.isBlackedOut {
                    Color.black
                }

                // swiftlint:disable hard_coded_display_string
                switch observer.status {
                case .loading:
                    ProgressView("Loading filter")

                case let .blocked(message):
                    VStack(spacing: 16) {
                        Image(systemName: "eye.slash")
                            .font(.largeTitle)
                        Text("Filtered playback is unavailable")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(message)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white)
                    .padding(48)

                case .unfiltered:
                    Label("Not filtered", systemImage: "eye")
                        .font(.caption)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(48)

                case .active:
                    EmptyView()
                }
                // swiftlint:enable hard_coded_display_string
            }
            .allowsHitTesting(false)
            .accessibilityHidden(!observer.isBlackedOut)
        }
    }
}
