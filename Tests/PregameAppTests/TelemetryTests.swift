import Foundation
import XCTest
@testable import PregameApp

/// Crash reports and usage data are opt-in (docs/privacy.md): nothing is
/// started or sent until the Mix Host says yes, and either can be turned off
/// again in Settings.
final class TelemetryTests: XCTestCase {
    private final class FakeCrashReporter: CrashReporting {
        var running = false
        var starts = 0
        func start() { running = true; starts += 1 }
        func stop() { running = false }
    }

    private final class Outbox: @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [URLRequest] = []
        var requests: [URLRequest] { lock.withLock { _requests } }
        func send(_ request: URLRequest) async { lock.withLock { _requests.append(request) } }
    }

    private var defaults: UserDefaults!
    private let crashes = FakeCrashReporter()
    private let outbox = Outbox()

    override func setUp() {
        defaults = UserDefaults(suiteName: "TelemetryTests-\(UUID())")
    }

    private func telemetry(configured: Bool = true) -> Telemetry {
        let outbox = outbox
        return Telemetry(defaults: defaults,
                         usageAppID: configured ? "APP-ID" : nil,
                         crashReporter: configured ? crashes : nil,
                         context: .init(appVersion: "1.2", buildNumber: "34", chip: "M4 Pro", memoryGB: 24),
                         send: { await outbox.send($0) })
    }

    /// Let any send that `record` started finish.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(50))
    }

    // MARK: - Consent off

    func testBeforeTheMixHostAnswersNothingIsStartedOrSent() async {
        let t = telemetry()
        t.start()
        t.record(.mixCreated)
        t.record(.tracksAdded(count: 3))
        await settle()
        XCTAssertEqual(crashes.starts, 0)
        XCTAssertTrue(outbox.requests.isEmpty)
    }

    // MARK: - The prompt

    func testSharingStartsCrashReportsAndSendsEvents() async {
        let t = telemetry()
        t.start()
        XCTAssertTrue(t.needsAnswer)
        t.answer(crashReports: true, usageData: true)
        XCTAssertFalse(t.needsAnswer)
        XCTAssertTrue(crashes.running)
        t.record(.mixCreated)
        await settle()
        XCTAssertEqual(outbox.requests.count, 1)
    }

    /// Several Mix windows can open at launch; only the first one asks.
    func testOnlyOneWindowAsks() {
        let t = telemetry()
        XCTAssertTrue(t.claimPrompt())
        XCTAssertFalse(t.claimPrompt())
        XCTAssertFalse(telemetry(configured: false).claimPrompt())
    }

    func testNoThanksStartsAndSendsNothingAndIsNotAskedAgain() async {
        telemetry().answer(crashReports: false, usageData: false)
        let relaunched = telemetry()
        relaunched.start()
        relaunched.record(.mixCreated)
        await settle()
        XCTAssertFalse(relaunched.needsAnswer)
        XCTAssertEqual(crashes.starts, 0)
        XCTAssertTrue(outbox.requests.isEmpty)
    }

    /// "Share selected" shares only what's ticked in the prompt.
    func testSharingOnlyCrashReportsSendsNoEvents() async {
        let t = telemetry()
        t.answer(crashReports: true, usageData: false)
        t.record(.mixCreated)
        await settle()
        XCTAssertFalse(t.needsAnswer)
        XCTAssertTrue(crashes.running)
        XCTAssertTrue(outbox.requests.isEmpty)
    }

    /// A build without the Sentry DSN and TelemetryDeck app ID (a local
    /// `swift run`) has nothing to share, so it doesn't ask.
    func testABuildWithNothingToShareNeverAsks() {
        XCTAssertFalse(telemetry(configured: false).needsAnswer)
    }

    // MARK: - Settings

    func testTheAnswerIsKeptAcrossLaunches() {
        telemetry().answer(crashReports: true, usageData: true)
        crashes.stop()
        telemetry().start()
        XCTAssertTrue(crashes.running)
    }

    func testTurningCrashReportsOffInSettingsStopsThem() {
        let t = telemetry()
        t.answer(crashReports: true, usageData: true)
        t.crashReports = false
        XCTAssertFalse(crashes.running)
        telemetry().start()
        XCTAssertFalse(crashes.running, "started again after a relaunch")
    }

    func testTurningUsageDataOffInSettingsStopsEventsButKeepsCrashReports() async {
        let t = telemetry()
        t.answer(crashReports: true, usageData: true)
        t.usageData = false
        t.record(.tracksAdded(count: 2))
        await settle()
        XCTAssertTrue(outbox.requests.isEmpty)
        XCTAssertTrue(crashes.running)
    }

    func testEitherCanBeTurnedOnLaterInSettings() async {
        let t = telemetry()
        t.answer(crashReports: false, usageData: false)
        t.usageData = true
        t.record(.mixCreated)
        await settle()
        XCTAssertEqual(outbox.requests.count, 1)
        XCTAssertFalse(crashes.running)
        t.crashReports = true
        XCTAssertTrue(crashes.running)
    }

    // MARK: - What a usage event sends

    private func sent(_ events: TelemetryEvent..., from t: Telemetry? = nil) async throws -> [[String: Any]] {
        let t = t ?? telemetry()
        t.answer(crashReports: true, usageData: true)
        for e in events { t.record(e) }
        await settle()
        return try outbox.requests.flatMap { r -> [[String: Any]] in
            XCTAssertEqual(r.url?.absoluteString, "https://nom.telemetrydeck.com/v2/")
            XCTAssertEqual(r.httpMethod, "POST")
            XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"), "application/json")
            return try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(r.httpBody)) as? [[String: Any]])
        }
    }

    /// One TelemetryDeck signal: the event's name, only the fields we list
    /// (docs/privacy.md), and an anonymous install ID.
    func testAnEventSendsItsNameAndOnlyTheListedFields() async throws {
        let signals = try await sent(.tracksAdded(count: 12))
        let signal = try XCTUnwrap(signals.first)
        XCTAssertEqual(signal["appID"] as? String, "APP-ID")
        XCTAssertEqual(signal["type"] as? String, "Tracks.added")
        XCTAssertEqual(signal["payload"] as? [String: String], [
            "appVersion": "1.2", "buildNumber": "34", "chip": "M4 Pro", "memoryGB": "24",
            "count": "12",
        ])
        XCTAssertEqual(signal["floatValue"] as? Double, 12)
        XCTAssertEqual(Set(signal.keys), ["appID", "type", "payload", "floatValue", "clientUser",
                                          "sessionID", "receivedAt", "isTestMode"])
        let date = try XCTUnwrap(signal["receivedAt"] as? String)
        XCTAssertNotNil(date.range(of: #"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\+0000$"#, options: .regularExpression), date)
    }

    func testAnExportSendsItsFormatAndDurations() async throws {
        let signals = try await sent(.exportFinished(format: .wavAndMP3, mixSeconds: 3725, exportSeconds: 94.6))
        let signal = try XCTUnwrap(signals.first)
        XCTAssertEqual(signal["type"] as? String, "Export.finished")
        let payload = try XCTUnwrap(signal["payload"] as? [String: String])
        XCTAssertEqual(payload["format"], "wav+mp3")
        XCTAssertEqual(payload["mixMinutes"], "62")
        XCTAssertEqual(payload["exportSeconds"], "95")
    }

    func testAnalysisSendsHowLongItTookForHowLongATrack() async throws {
        let signals = try await sent(.trackAnalysed(seconds: 4.26, trackSeconds: 251))
        let signal = try XCTUnwrap(signals.first)
        XCTAssertEqual(signal["type"] as? String, "Track.analysed")
        let payload = try XCTUnwrap(signal["payload"] as? [String: String])
        XCTAssertEqual(payload["analysisSeconds"], "4.3")
        XCTAssertEqual(payload["trackMinutes"], "4")
        XCTAssertEqual(signal["floatValue"] as? Double, 4.3)
    }

    /// The install ID is a random UUID kept in the app's settings and only
    /// ever sent hashed; the session ID is new each launch.
    func testTheInstallIDIsHashedAndStableAndTheSessionIsPerLaunch() async throws {
        let first = try await sent(.mixCreated, .mixCreated)
        let second = try await sent(.mixCreated, from: telemetry())
        let users = Set((first + second).compactMap { $0["clientUser"] as? String })
        XCTAssertEqual(users.count, 1)
        let user = try XCTUnwrap(users.first)
        XCTAssertNotNil(user.range(of: "^[0-9a-f]{64}$", options: .regularExpression), user)
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { $0 as? String == user },
                       "the install ID went out as stored, not hashed")
        XCTAssertEqual(first[0]["sessionID"] as? String, first[1]["sessionID"] as? String)
        XCTAssertNotEqual(first[0]["sessionID"] as? String, second[2]["sessionID"] as? String)
    }
}
