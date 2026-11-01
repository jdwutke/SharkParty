//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where a title's scan stands on the server, as reported alongside a 404 or 409.
public struct ScanStatus: Sendable, Equatable, Decodable {

    public enum State: String, Sendable, Equatable, Decodable {
        case queued
        case running
        case done
        case failed
        case unknown

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = State(rawValue: raw) ?? .unknown
        }
    }

    public let state: State
    public let stage: String?
    public let error: String?

    public init(state: State, stage: String? = nil, error: String? = nil) {
        self.state = state
        self.stage = stage
        self.error = error
    }

    /// Whether a scan is already under way, so asking again would only wait in line.
    public var isActive: Bool {
        state == .queued || state == .running
    }

    /// One line for the viewer.
    public var progressText: String {
        switch state {
        case .queued:
            return "Waiting to be filtered."

        case .running:
            let step: String = switch stage {
            case "resolve", "probe": "Reading the file."
            case "audio": "Extracting the soundtrack."
            case "transcript": "Listening for language. This takes the longest."
            case "language": "Marking language."
            case "nudity": "Checking the picture for nudity."
            case "publish": "Almost done."
            default: "Working."
            }
            return "Filtering this title now. \(step)"

        case .done:
            return "Filtering finished. Loading the filter."

        case .failed:
            return "Filtering this title failed\(error.map { ": \($0)" } ?? ".")"

        case .unknown:
            return "Filtering is in an unknown state."
        }
    }
}

public extension FilterRequest {

    /// Asks the server to scan a title. Allowed with the read key.
    static func scan(server: URL, itemID: String, apiKey: String) -> URLRequest? {
        let guidCharacters = CharacterSet(charactersIn: "0123456789abcdefABCDEF-")
        guard !itemID.isEmpty, itemID.unicodeScalars.allSatisfy(guidCharacters.contains), !apiKey.isEmpty else {
            return nil
        }

        var request = URLRequest(
            url: server.appendingPathComponent("api/v1/items/\(itemID)/scan", isDirectory: false),
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 10
        )
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: apiKeyHeader)
        return request
    }
}
