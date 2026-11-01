//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
@testable import GuardarrFilterKit
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let allCategories = Set(FilterCategory.allCases)
private let allPrefs = FilterPreferences(categories: allCategories)

private func event(_ action: FilterAction, _ start: Int64, _ end: Int64, _ category: FilterCategory = .violence) -> FilterEvent {
    FilterEvent(action: action, category: category, startMs: start, endMs: end)
}

private func json(_ string: String) -> Data {
    Data(string.utf8)
}

private let listBody = json("""
{"schema":1,"itemId":"0123456789abcdef0123456789abcdef","revision":2,"updatedAt":"2026-11-01T00:00:00Z",
 "file":{"path":"/m/x.mkv","sizeBytes":1000,"durationMs":6000000},
 "coverage":["language","nudity","future-thing"],
 "events":[{"action":"mute","category":"language","startMs":1000,"endMs":1400,"label":"f-word"},
           {"action":"zoom","category":"drugs","startMs":5000,"endMs":6000,"label":null}]}
""")

struct FetchResultTests {

    @Test
    func `200 decodes the list and maps unknown values to the strictest choice`() {
        let result = FilterFetchResult.from(status: 200, body: listBody, requestedSizeBytes: 1000)
        guard case let .filtered(list) = result else {
            Issue.record("expected .filtered, got \(result)")
            return
        }

        #expect(list.revision == 2)
        #expect(list.events.count == 2)
        #expect(list.events[0] == FilterEvent(action: .mute, category: .language, startMs: 1000, endMs: 1400, label: "f-word"))
        #expect(list.events[1].action == .blackout)
        #expect(list.events[1].category == .other)
    }

    @Test
    func `200 for another title or a newer schema fails`() {
        let otherTitle = FilterFetchResult.from(
            status: 200,
            body: listBody,
            requestedSizeBytes: 1000,
            requestedItemID: "ffffffffffffffffffffffffffffffff"
        )
        if case .failed = otherTitle {} else {
            Issue.record("a list for another title must fail, got \(otherTitle)")
        }
        let sameTitleDashed = FilterFetchResult.from(
            status: 200,
            body: listBody,
            requestedSizeBytes: 1000,
            requestedItemID: "01234567-89AB-CDEF-0123-456789ABCDEF"
        )
        if case .filtered = sameTitleDashed {} else {
            Issue.record("dashed, uppercase id of the same title must match, got \(sameTitleDashed)")
        }
        let newer = Data(String(decoding: listBody, as: UTF8.self).replacing("\"schema\":1", with: "\"schema\":2").utf8)
        if case .failed = FilterFetchResult.from(status: 200, body: newer, requestedSizeBytes: 1000) {} else {
            Issue.record("schema 2 must fail")
        }
    }

    @Test
    func `200 for a different file size is treated as a changed file`() {
        #expect(FilterFetchResult.from(status: 200, body: listBody, requestedSizeBytes: 999) == .fileChanged(nil))
    }

    @Test
    func `only the service's own 404 and 409 answers are trusted`() {
        #expect(FilterFetchResult.from(status: 404, body: json(#"{"status":"not_filtered"}"#), requestedSizeBytes: 1) == .notFiltered(nil))
        #expect(FilterFetchResult.from(status: 409, body: json(#"{"status":"file_changed"}"#), requestedSizeBytes: 1) == .fileChanged(nil))
        if case .failed = FilterFetchResult.from(status: 404, body: json("<html>Not Found</html>"), requestedSizeBytes: 1) {} else {
            Issue.record("a bare 404 must not mean 'not filtered'")
        }
        if case .failed = FilterFetchResult.from(status: 409, body: Data(), requestedSizeBytes: 1) {} else {
            Issue.record("a bare 409 must fail")
        }
    }

    @Test
    func `malformed or inverted lists fail instead of applying`() {
        let inverted = json("""
        {"schema":1,"itemId":"a","revision":1,"file":{"sizeBytes":1},"events":[{"action":"mute","category":"language","startMs":9,"endMs":3}]}
        """)
        for body in [json("{}"), json("not json"), inverted] {
            if case .failed = FilterFetchResult.from(status: 200, body: body, requestedSizeBytes: 1) {} else {
                Issue.record("expected .failed for \(String(decoding: body, as: UTF8.self))")
            }
        }
    }

    @Test
    func `other statuses fail and 401 is unauthorized`() {
        #expect(FilterFetchResult.from(status: 401, body: Data(), requestedSizeBytes: 1) == .unauthorized)
        if case .failed = FilterFetchResult.from(status: 500, body: Data(), requestedSizeBytes: 1) {} else {
            Issue.record("500 must fail")
        }
    }
}

struct RequestTests {

    @Test
    func `request carries the key and file size`() throws {
        let server = try #require(URL(string: "http://10.10.110.25:8787"))
        let request = try #require(FilterRequest.make(
            server: server,
            itemID: "0123456789abcdef0123456789abcdef",
            fileSizeBytes: 4_823_123_456,
            apiKey: "key"
        ))
        #expect(request.url?.absoluteString
            == "http://10.10.110.25:8787/api/v1/items/0123456789abcdef0123456789abcdef/filters?sizeBytes=4823123456")
        #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "key")
    }

    @Test
    func `request is refused without a size, id or key`() throws {
        let server = try #require(URL(string: "http://h:1"))
        #expect(FilterRequest.make(server: server, itemID: "a", fileSizeBytes: 0, apiKey: "k") == nil)
        #expect(FilterRequest.make(server: server, itemID: "", fileSizeBytes: 1, apiKey: "k") == nil)
        #expect(FilterRequest.make(server: server, itemID: "a", fileSizeBytes: 1, apiKey: "") == nil)
    }

    @Test
    func `a non-GUID item id is refused rather than put in the path`() throws {
        let server = try #require(URL(string: "http://h:1"))
        #expect(FilterRequest.make(server: server, itemID: "../x?y", fileSizeBytes: 1, apiKey: "k") == nil)
        #expect(FilterRequest.make(server: server, itemID: "01234567-89AB-cdef-0123-456789abcdef", fileSizeBytes: 1, apiKey: "k") != nil)
    }
}

struct GateTests {

    private let list = FilterList(
        schema: 1,
        itemID: "a",
        revision: 1,
        fileSizeBytes: 1,
        events: [event(.mute, 0, 10)],
        coverage: Set(FilterCategory.allCases)
    )

    @Test
    func `only a matching list lets filtered playback start`() {
        #expect(FilterGate.decide(.filtered(list), preferences: allPrefs, allowUnfilteredTitles: false)
            == .apply(FilterTimeline(events: list.events, preferences: allPrefs)))
        #expect(FilterGate
            .decide(.notFiltered(nil), preferences: allPrefs, allowUnfilteredTitles: false) == .block(.notFiltered(nil)))
        #expect(FilterGate
            .decide(.fileChanged(nil), preferences: allPrefs, allowUnfilteredTitles: true) == .block(.fileChanged(nil)))
        #expect(FilterGate.decide(.unauthorized, preferences: allPrefs, allowUnfilteredTitles: true) == .block(.unauthorized))
        #expect(FilterGate.decide(.failed("x"), preferences: allPrefs, allowUnfilteredTitles: true) == .block(.failed("x")))
    }

    @Test
    func `allowing unfiltered titles only covers titles without a list`() {
        #expect(FilterGate.decide(.notFiltered(nil), preferences: allPrefs, allowUnfilteredTitles: true) == .allowUnfiltered)
    }
}

struct TimelineTests {

    @Test
    func `skip implies blackout and mute; blackout implies mute`() {
        let timeline = FilterTimeline(
            events: [event(.skip, 100, 200), event(.blackout, 300, 400), event(.mute, 500, 600)],
            preferences: allPrefs
        )
        #expect(timeline.state(from: 150, through: 150) == FilterState(muted: true, blackedOut: true, skipTo: 200, skipFrom: 100))
        #expect(timeline.state(from: 350, through: 350) == FilterState(muted: true, blackedOut: true, skipTo: nil, skipFrom: nil))
        #expect(timeline.state(from: 550, through: 550) == FilterState(muted: true, blackedOut: false, skipTo: nil, skipFrom: nil))
        #expect(timeline.state(from: 650, through: 650) == .clear)
    }

    @Test
    func `ranges are half-open`() {
        let timeline = FilterTimeline(events: [event(.mute, 100, 200)], preferences: allPrefs)
        #expect(timeline.state(from: 99, through: 99) == .clear)
        #expect(timeline.state(from: 100, through: 100).muted)
        #expect(timeline.state(from: 199, through: 199).muted)
        #expect(timeline.state(from: 200, through: 200) == .clear)
    }

    @Test
    func `a short word between two samples is still caught`() {
        let timeline = FilterTimeline(events: [event(.mute, 1020, 1040, .language)], preferences: allPrefs)
        #expect(timeline.state(from: 1000, through: 1050).muted)
    }

    @Test
    func `overlapping and touching skips chain to one seek`() {
        let timeline = FilterTimeline(
            events: [event(.skip, 100, 200), event(.skip, 200, 300), event(.skip, 250, 500)],
            preferences: allPrefs
        )
        #expect(timeline.skipRanges == [FilterRange(start: 100, end: 500)])
        #expect(timeline.state(from: 120, through: 120).skipTo == 500)
    }

    @Test
    func `disabled categories are dropped but other is always kept`() {
        let timeline = FilterTimeline(
            events: [event(.mute, 0, 10, .language), event(.skip, 20, 30, .violence), event(.blackout, 40, 50, .other)],
            preferences: FilterPreferences(categories: [.nudity])
        )
        #expect(timeline.state(from: 5, through: 5) == .clear)
        #expect(timeline.state(from: 25, through: 25) == .clear)
        #expect(timeline.state(from: 45, through: 45).blackedOut)
    }

    @Test
    func `binary search agrees with a linear scan`() {
        var events: [FilterEvent] = []
        var seed: UInt64 = 42
        func next(_ bound: Int64) -> Int64 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Int64(seed >> 33) % bound
        }
        for _ in 0 ..< 300 {
            let start = next(100_000)
            events.append(event(.mute, start, start + 1 + next(800)))
        }
        let timeline = FilterTimeline(events: events, preferences: allPrefs)
        for _ in 0 ..< 2000 {
            let low = next(101_000)
            let high = low + next(300)
            let expected = events.contains { $0.startMs <= high && $0.endMs > low }
            #expect(timeline.state(from: low, through: high).muted == expected)
        }
    }
}

struct ControllerTests {

    @Test
    func `filtering starts lead milliseconds early`() {
        var controller = FilterController(
            timeline: FilterTimeline(events: [event(.mute, 1000, 1400)], preferences: allPrefs),
            leadMs: 150
        )
        #expect(!controller.update(confirmedMs: 800, estimatedMs: 840).muted)
        #expect(controller.update(confirmedMs: 800, estimatedMs: 860).muted)
    }

    @Test
    func `filtering ends only after the player confirms it is past the range`() {
        var controller = FilterController(
            timeline: FilterTimeline(events: [event(.mute, 1000, 1400)], preferences: allPrefs),
            leadMs: 0
        )
        // Estimated past the end, but the player last reported a position inside.
        #expect(controller.update(confirmedMs: 1300, estimatedMs: 1500).muted)
        #expect(!controller.update(confirmedMs: 1450, estimatedMs: 1460).muted)
    }

    @Test
    func `a skip stays dark until the player has played past the target`() {
        var controller = FilterController(
            timeline: FilterTimeline(events: [event(.skip, 1000, 5000)], preferences: allPrefs),
            leadMs: 0
        )
        #expect(controller.update(confirmedMs: 1000, estimatedMs: 1000) == FilterCommand(muted: true, blackedOut: true, seekToMs: 5000))
        // Some players report the target the moment a seek is requested, before it lands.
        #expect(controller.update(confirmedMs: 5000, estimatedMs: 5000) == FilterCommand(muted: true, blackedOut: true, seekToMs: nil))
        #expect(controller.update(confirmedMs: 5100, estimatedMs: 5100) == FilterCommand(muted: true, blackedOut: true, seekToMs: nil))
        #expect(controller.update(confirmedMs: 5300, estimatedMs: 5300) == FilterCommand(muted: false, blackedOut: false, seekToMs: nil))
    }

    @Test
    func `late reports from before the seek neither unblank nor re-seek`() {
        var controller = FilterController(
            timeline: FilterTimeline(events: [event(.skip, 1000, 5000)], preferences: allPrefs),
            leadMs: 0
        )
        _ = controller.update(confirmedMs: 1000, estimatedMs: 1000)
        _ = controller.update(confirmedMs: 5000, estimatedMs: 5000)
        // A stale report lands inside the range and looks like a backward jump.
        controller.viewerDidSeek()
        #expect(controller.update(confirmedMs: 1200, estimatedMs: 1200) == FilterCommand(muted: true, blackedOut: true, seekToMs: nil))
        #expect(controller.update(confirmedMs: 900, estimatedMs: 900) == FilterCommand(muted: true, blackedOut: true, seekToMs: nil))
    }

    @Test
    func `a seek that lands short plays out the range dark without seeking again`() {
        var controller = FilterController(
            timeline: FilterTimeline(events: [event(.skip, 1000, 5000)], preferences: allPrefs),
            leadMs: 0
        )
        _ = controller.update(confirmedMs: 1000, estimatedMs: 1000)
        for position in stride(from: Int64(4800), through: 5200, by: 100) {
            #expect(controller.update(confirmedMs: position, estimatedMs: position) == FilterCommand(
                muted: true,
                blackedOut: true,
                seekToMs: nil
            ))
        }
        #expect(!controller.update(confirmedMs: 5300, estimatedMs: 5300).blackedOut)
    }

    @Test
    func `the viewer seeking far back ends the in-flight wait`() {
        var controller = FilterController(
            timeline: FilterTimeline(events: [event(.skip, 10000, 50000)], preferences: allPrefs),
            leadMs: 0
        )
        _ = controller.update(confirmedMs: 10000, estimatedMs: 10000)
        #expect(controller.update(confirmedMs: 2000, estimatedMs: 2000) == FilterCommand(muted: false, blackedOut: false, seekToMs: nil))
        // Playing back into the range skips it again.
        #expect(controller.update(confirmedMs: 10000, estimatedMs: 10000).seekToMs == 50000)
    }

    @Test
    func `a viewer seek back into the range after landing skips again`() {
        var controller = FilterController(
            timeline: FilterTimeline(events: [event(.skip, 1000, 5000)], preferences: allPrefs),
            leadMs: 0
        )
        _ = controller.update(confirmedMs: 1000, estimatedMs: 1000)
        _ = controller.update(confirmedMs: 5300, estimatedMs: 5300)
        // Straight from past the range to inside it, with no update in between.
        #expect(controller.update(confirmedMs: 3000, estimatedMs: 3000).seekToMs == 5000)
    }

    @Test
    func `audio offset widens mutes on the side sound is shifted`() {
        let timeline = FilterTimeline(events: [event(.mute, 1000, 1400, .language)], preferences: allPrefs)
        var delayed = FilterController(timeline: timeline, leadMs: 0)
        // Sound 300 ms late: what is heard at 1600 was content at 1300.
        #expect(delayed.update(confirmedMs: 1600, estimatedMs: 1600, audioOffsetMs: 300).muted)
        #expect(!delayed.update(confirmedMs: 1800, estimatedMs: 1800, audioOffsetMs: 300).muted)
        var early = FilterController(timeline: timeline, leadMs: 0)
        // Sound 300 ms early: content at 1000 is heard at 700.
        #expect(early.update(confirmedMs: 750, estimatedMs: 750, audioOffsetMs: -300).muted)
        #expect(!early.update(confirmedMs: 650, estimatedMs: 650, audioOffsetMs: -300).muted)
    }

    @Test
    func `the lead scales with playback rate`() {
        let timeline = FilterTimeline(events: [event(.mute, 1000, 1400)], preferences: allPrefs)
        var normal = FilterController(timeline: timeline, leadMs: 150)
        #expect(!normal.update(confirmedMs: 800, estimatedMs: 800, rate: 1).muted)
        var fast = FilterController(timeline: timeline, leadMs: 150)
        #expect(fast.update(confirmedMs: 800, estimatedMs: 800, rate: 2).muted)
    }

    @Test
    func `an unfiltered stretch issues nothing`() {
        var controller = FilterController(timeline: FilterTimeline(events: [], preferences: allPrefs))
        #expect(controller.update(confirmedMs: 0, estimatedMs: 10000) == FilterCommand(muted: false, blackedOut: false, seekToMs: nil))
    }
}

struct ClockTests {

    @Test
    func `extrapolates while playing, capped, and holds while paused`() {
        var clock = PlaybackClock()
        #expect(clock.estimate(at: 0) == nil)
        clock.record(positionMs: 10000, at: 100, rate: 1, isPlaying: true)
        #expect(clock.estimate(at: 100.25) == 10250)
        #expect(clock.estimate(at: 105) == 11000)
        clock.record(positionMs: 10000, at: 100, rate: 2, isPlaying: true)
        #expect(clock.estimate(at: 100.25) == 10500)
        clock.record(positionMs: 10000, at: 100, rate: 1, isPlaying: false)
        #expect(clock.estimate(at: 104) == 10000)
    }
}

struct CoverageAndScanTests {

    private func list(coverage: Set<FilterCategory>) -> FilterList {
        FilterList(schema: 1, itemID: "a", revision: 1, fileSizeBytes: 1, events: [], coverage: coverage)
    }

    @Test
    func `coverage decodes and drops unknown categories`() {
        guard case let .filtered(decoded) = FilterFetchResult.from(status: 200, body: listBody, requestedSizeBytes: 1000) else {
            Issue.record("expected a list")
            return
        }

        #expect(decoded.coverage == [.language, .nudity])
    }

    @Test
    func `a list without coverage vouches for nothing`() {
        let body = json(#"{"schema":1,"itemId":"a","revision":1,"file":{"sizeBytes":1},"events":[]}"#)
        guard case let .filtered(decoded) = FilterFetchResult.from(status: 200, body: body, requestedSizeBytes: 1) else {
            Issue.record("expected a list")
            return
        }

        #expect(decoded.coverage.isEmpty)
        #expect(FilterGate.decide(.filtered(decoded), preferences: FilterPreferences(categories: [.language]), allowUnfilteredTitles: true)
            == .block(.notFullyScanned([.language])))
    }

    @Test
    func `a category the viewer filters but the file wasn't scanned for blocks`() {
        let result = FilterFetchResult.filtered(list(coverage: [.language]))
        #expect(FilterGate.decide(result, preferences: FilterPreferences(categories: [.language, .nudity]), allowUnfilteredTitles: true)
            == .block(.notFullyScanned([.nudity])))
        if case .apply = FilterGate
            .decide(result, preferences: FilterPreferences(categories: [.language]), allowUnfilteredTitles: false) {} else
        {
            Issue.record("a fully covered list must apply")
        }
    }

    @Test
    func `other never needs coverage`() {
        let result = FilterFetchResult.filtered(list(coverage: [.language]))
        if case .apply = FilterGate.decide(
            result,
            preferences: FilterPreferences(categories: [.language, .other]),
            allowUnfilteredTitles: false
        ) {} else {
            Issue.record("other is always filtered but never scanned for, so it must not block")
        }
    }

    @Test
    func `scan status rides along on 404 and 409`() {
        let notFiltered = json(#"{"status":"not_filtered","scan":{"state":"running","stage":"transcript","attempts":1,"error":null}}"#)
        #expect(FilterFetchResult.from(status: 404, body: notFiltered, requestedSizeBytes: 1)
            == .notFiltered(ScanStatus(state: .running, stage: "transcript")))
        let changed = json(#"{"status":"file_changed","scan":{"state":"weird"}}"#)
        #expect(FilterFetchResult.from(status: 409, body: changed, requestedSizeBytes: 1) == .fileChanged(ScanStatus(state: .unknown)))
        let noScan = json(#"{"status":"not_filtered","scan":null}"#)
        #expect(FilterFetchResult.from(status: 404, body: noScan, requestedSizeBytes: 1) == .notFiltered(nil))
    }

    @Test
    func `a scan is requested only when none is waiting or running`() {
        #expect(FilterGate.shouldRequestScan(.notFiltered(nil)))
        #expect(FilterGate.shouldRequestScan(.fileChanged(nil)))
        #expect(FilterGate.shouldRequestScan(.notFiltered(ScanStatus(state: .failed))))
        #expect(FilterGate.shouldRequestScan(.notFiltered(ScanStatus(state: .done))))
        #expect(!FilterGate.shouldRequestScan(.notFiltered(ScanStatus(state: .queued))))
        #expect(!FilterGate.shouldRequestScan(.fileChanged(ScanStatus(state: .running))))
        #expect(!FilterGate.shouldRequestScan(.unauthorized))
        #expect(!FilterGate.shouldRequestScan(.failed("x")))
    }

    @Test
    func `the player keeps waiting only while a scan is active`() {
        #expect(FilterGate.isWaitingForScan(.notFiltered(ScanStatus(state: .queued))))
        #expect(FilterGate.isWaitingForScan(.fileChanged(ScanStatus(state: .running))))
        #expect(!FilterGate.isWaitingForScan(.notFiltered(ScanStatus(state: .failed))))
        #expect(FilterGate.isWaitingForScan(.notFiltered(ScanStatus(state: .done))), "a just-finished scan's list is fetched")
        #expect(!FilterGate.isWaitingForScan(.notFiltered(nil)))
    }

    @Test
    func `scan request is a keyed POST and refuses a bad id`() throws {
        let server = try #require(URL(string: "http://h:1"))
        let request = try #require(FilterRequest.scan(server: server, itemID: "0123456789abcdef0123456789abcdef", apiKey: "k"))
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/v1/items/0123456789abcdef0123456789abcdef/scan")
        #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "k")
        #expect(FilterRequest.scan(server: server, itemID: "../x", apiKey: "k") == nil)
    }

    @Test
    func `progress text names the stage`() {
        #expect(ScanStatus(state: .running, stage: "transcript").progressText.contains("Listening for language"))
        #expect(ScanStatus(state: .failed, error: "no audio").progressText.contains("no audio"))
        #expect(FilterBlockReason.notFiltered(ScanStatus(state: .queued)).message == "Waiting to be filtered.")
        #expect(FilterBlockReason.notFullyScanned([.nudity, .gore]).message.contains("gore or nudity"))
    }

    @Test
    func `a scan request reply updates the waiting result`() {
        let reply = json(#"{"itemId":"a","scan":{"state":"queued","stage":null,"attempts":0,"error":null}}"#)
        let scan = FilterFetchResult.scan(in: reply)
        #expect(scan == ScanStatus(state: .queued))
        let updated = FilterFetchResult.notFiltered(nil).withScan(scan)
        #expect(FilterGate.isWaitingForScan(updated))
        #expect(!FilterGate.shouldRequestScan(updated))
        #expect(FilterFetchResult.unauthorized.withScan(scan) == .unauthorized)
    }
}
