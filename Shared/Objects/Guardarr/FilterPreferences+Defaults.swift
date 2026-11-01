//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation
import GuardarrFilterKit

extension FilterPreferences: @retroactive Defaults.Serializable {}

extension FilterPreferences {

    /// What a viewer gets before saving preferences. A viewer who chose categories under
    /// the original key keeps muting every language level; a new install gets the defaults.
    static var legacyDefault: FilterPreferences {
        let legacyKey = Defaults.Keys.Guardarr.enabledCategories
        let legacy = UserDefaults.standard.object(forKey: legacyKey.name) == nil ? nil : Defaults[legacyKey]
        return .upgrading(fromEnabledCategories: legacy)
    }

    /// The current user's preferences.
    ///
    /// Which categories are on lives in the original `enabledCategories` key, so what
    /// viewers already chose carries over. Everything else (levels, words, actions) is
    /// in the `preferences` key, whose own `categories` field isn't used.
    static var current: FilterPreferences {
        var preferences = Defaults[.Guardarr.preferences]
        preferences.categories = Set(Defaults[.Guardarr.enabledCategories].compactMap(FilterCategory.init(rawValue:)))
        return preferences
    }
}
