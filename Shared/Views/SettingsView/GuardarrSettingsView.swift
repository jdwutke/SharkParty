//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import GuardarrFilterKit
import SwiftUI

/// Guardarr content filtering for the current user.
struct GuardarrSettingsView: View {

    @Default(.Guardarr.isEnabled)
    private var isEnabled
    @Default(.Guardarr.serverURL)
    private var serverURL
    @Default(.Guardarr.apiKey)
    private var apiKey
    @Default(.Guardarr.allowUnfilteredTitles)
    private var allowUnfilteredTitles
    @Default(.Guardarr.enabledCategories)
    private var enabledCategories

    // swiftlint:disable hard_coded_display_string
    var body: some View {
        Form(systemImage: "eye.slash") {
            Section {
                Toggle("Filter playback", isOn: $isEnabled)
            } footer: {
                Text("Mutes, blacks out or skips content using filter lists from your Guardarr server. Applies to this user only.")
            }

            Section("Server") {
                TextField("Server address", text: $serverURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("Key", text: $apiKey)
            }

            Section {
                Toggle("Play titles that aren't filtered yet", isOn: $allowUnfilteredTitles)
            } footer: {
                Text("A filter made for a file that was later replaced is never applied, even with this on.")
            }

            Section("Filter") {
                ForEach(FilterCategory.allCases.filter { $0 != .other }, id: \.self) { category in
                    Toggle(title(for: category), isOn: binding(for: category))
                }
            }
        }
        .navigationTitle("Content filter")
    }

    private func title(for category: FilterCategory) -> String {
        switch category {
        case .language: "Language"
        case .nudity: "Nudity"
        case .sexual: "Sexual content"
        case .violence: "Violence"
        case .gore: "Gore"
        case .other: "Other"
        }
    }

    // swiftlint:enable hard_coded_display_string

    private func binding(for category: FilterCategory) -> Binding<Bool> {
        Binding {
            enabledCategories.contains(category.rawValue)
        } set: { isOn in
            var categories = Set(enabledCategories)
            if isOn {
                categories.insert(category.rawValue)
            } else {
                categories.remove(category.rawValue)
            }
            enabledCategories = FilterCategory.allCases.map(\.rawValue).filter(categories.contains)
        }
    }
}
