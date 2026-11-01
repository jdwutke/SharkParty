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

/// Builds the request for a title's filter list.
public enum FilterRequest {

    public static let apiKeyHeader = "X-Api-Key"

    /// - Parameters:
    ///   - server: the filter service base URL, for example `http://10.10.110.25:8787`.
    ///   - itemID: the Deadfin or Jellyfin item id.
    ///   - fileSizeBytes: the size of the media source about to play. The server refuses
    ///     to return a list made for a different file.
    public static func make(server: URL, itemID: String, fileSizeBytes: Int64, apiKey: String) -> URLRequest? {
        // Item ids are GUIDs. Anything else is refused rather than escaped into the path.
        let guidCharacters = CharacterSet(charactersIn: "0123456789abcdefABCDEF-")
        guard !itemID.isEmpty, itemID.unicodeScalars.allSatisfy(guidCharacters.contains),
              fileSizeBytes > 0, !apiKey.isEmpty,
              var components = URLComponents(
                  url: server.appendingPathComponent("api/v1/items/\(itemID)/filters", isDirectory: false),
                  resolvingAgainstBaseURL: false
              )
        else { return nil }

        components.queryItems = [URLQueryItem(name: "sizeBytes", value: String(fileSizeBytes))]

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue(apiKey, forHTTPHeaderField: apiKeyHeader)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

/// The outcome of asking the filter service for a title's list.
public enum FilterFetchResult: Sendable, Equatable {

    case filtered(FilterList)
    case notFiltered
    case fileChanged
    case unauthorized
    case failed(String)

    /// The filter list format this client understands.
    public static let supportedSchema = 1

    /// Interprets a completed HTTP exchange. Anything unexpected is `.failed`, never `.filtered`.
    public static func from(
        status: Int,
        body: Data,
        requestedSizeBytes: Int64,
        requestedItemID: String? = nil
    ) -> FilterFetchResult {
        switch status {
        case 200:
            guard let list = try? JSONDecoder().decode(FilterList.self, from: body) else {
                return .failed("The filter server sent a list this app can't read.")
            }

            // The server already checks this. Checking again means a server bug can't
            // apply another file's timings.
            guard list.schema == supportedSchema else {
                return .failed("The filter server uses a newer filter format. Update this app.")
            }

            if let requestedItemID, normalized(list.itemID) != normalized(requestedItemID) {
                return .failed("The filter server sent the list for a different title.")
            }
            guard list.fileSizeBytes == requestedSizeBytes else { return .fileChanged }

            return .filtered(list)

        case 401:
            return .unauthorized

        // A bare 404 or 409, from a wrong address or a proxy, must not read as
        // "this title has no filter list". Only the filter service's own answer counts.
        case 404 where serviceStatus(in: body) == "not_filtered":
            return .notFiltered

        case 409 where serviceStatus(in: body) == "file_changed":
            return .fileChanged

        default:
            return .failed("The filter server answered with HTTP \(status).")
        }
    }

    private static func normalized(_ itemID: String) -> String {
        itemID.replacing("-", with: "").lowercased()
    }

    private struct ServiceStatus: Decodable {
        let status: String
    }

    private static func serviceStatus(in body: Data) -> String? {
        (try? JSONDecoder().decode(ServiceStatus.self, from: body))?.status
    }
}
