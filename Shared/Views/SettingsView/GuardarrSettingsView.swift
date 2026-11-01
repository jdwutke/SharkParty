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
    @Default(.Guardarr.preferences)
    private var preferences

    /// Words from the filter presets that are common enough to be worth a switch.
    private static let commonWords = ["damn", "goddamn", "hell", "crap", "ass", "bastard", "piss", "shit", "bitch"]

    private enum WordChoice: String, CaseIterable {
        case standard = "Use level"
        case allow = "Allow"
        case block = "Always mute"
    }

    // swiftlint:disable hard_coded_display_string
    var body: some View {
        Form(systemImage: "eye.slash") {
            Section {
                Toggle("Filter playback", isOn: $isEnabled)
            } footer: {
                Text("Mutes, blacks out or skips content using filter lists from your Guardarr server. Applies to this user only.")
            }

            Section {
                Toggle("Language", isOn: binding(for: .language))
                Toggle("Mild: damn, hell", isOn: severityBinding(.mild))
                Toggle("Moderate: shit, bitch", isOn: severityBinding(.moderate))
                Toggle("Strong: f-word, slurs", isOn: severityBinding(.strong))
            } header: {
                Text("Language")
            } footer: {
                Text("Chosen levels are muted.")
            }

            Section {
                Toggle("Nudity", isOn: binding(for: .nudity))
                Toggle("Include bare buttocks", isOn: $preferences.includePartialNudity)
                Picker("When it appears", selection: $preferences.nudityAction) {
                    Text("Skip").tag(NudityAction.skip)
                    Text("Black out").tag(NudityAction.blackout)
                }
            } header: {
                Text("Nudity")
            } footer: {
                Text("Bare breasts and genitals are always included. Bare buttocks includes thongs and G-strings.")
            }

            Section {
                ForEach(Self.commonWords, id: \.self) { word in
                    Picker(word, selection: wordBinding(word)) {
                        ForEach(WordChoice.allCases, id: \.self) { choice in
                            Text(choice.rawValue).tag(choice)
                        }
                    }
                }
            } header: {
                Text("Words")
            } footer: {
                Text("Allow a word to hear it even when its level is muted, or always mute it. Needs language on.")
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
        }
        .navigationTitle("Content filter")
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

    private func severityBinding(_ severity: FilterSeverity) -> Binding<Bool> {
        Binding {
            preferences.mutedSeverities.contains(severity)
        } set: { isOn in
            if isOn {
                preferences.mutedSeverities.insert(severity)
            } else {
                preferences.mutedSeverities.remove(severity)
            }
        }
    }

    private func wordBinding(_ word: String) -> Binding<WordChoice> {
        Binding {
            if preferences.blockedWords.contains(word) {
                .block
            } else if preferences.allowedWords.contains(word) {
                .allow
            } else {
                .standard
            }
        } set: { choice in
            preferences.allowedWords.remove(word)
            preferences.blockedWords.remove(word)
            switch choice {
            case .standard: break
            case .allow: preferences.allowedWords.insert(word)
            case .block: preferences.blockedWords.insert(word)
            }
        }
    }
}
