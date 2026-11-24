import Foundation
import XCTest
@testable import PregameApp

/// docs/privacy.md is the published list of everything Pregame can send. These
/// keep it in step with the code, and check where it's linked from.
final class PrivacyDocsTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func read(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Every event's name and every field it sends appear in the doc, as `code`.
    func testThePrivacyDocListsEveryEventAndField() throws {
        let doc = try read("docs/privacy.md")
        let context = Telemetry.Context(appVersion: "1", buildNumber: "1", chip: "M1", memoryGB: 8)
        for event in TelemetryEvent.examples {
            XCTAssertTrue(doc.contains("`\(event.name)`"), "\(event.name) isn't listed")
            let signal = UsageSignal(appID: "A", clientUser: "U", sessionID: "S", event: event, context: context)
            for field in signal.payload.keys {
                XCTAssertTrue(doc.contains("`\(field)`"), "\(event.name)'s field \(field) isn't listed")
            }
        }
        for field in ["clientUser", "sessionID", "floatValue", "isTestMode"] {
            XCTAssertTrue(doc.contains("`\(field)`"), "the signal field \(field) isn't explained")
        }
    }

    /// The app's prompt and Settings link to the published doc, and so does the README.
    func testTheDocIsLinkedFromTheAppAndTheReadme() throws {
        XCTAssertEqual(privacyDocURL.absoluteString, "https://github.com/Praful-Joshi/pregame/blob/main/docs/privacy.md")
        XCTAssertTrue(try read("README.md").contains("docs/privacy.md"))
    }

    /// Release builds carry the Sentry DSN and TelemetryDeck app ID in Info.plist.
    func testInfoPlistHasTheTelemetryKeys() throws {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("scripts/Info.plist"))
        let info = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertNotNil(info["PregameSentryDSN"] as? String)
        XCTAssertNotNil(info["PregameTelemetryDeckAppID"] as? String)
    }

    /// Sentry's macOS framework is dynamic, so build-app.sh embeds it and signs
    /// it with the app's identity (the hardened runtime loads nothing else).
    func testTheBuildEmbedsAndSignsSentry() throws {
        let script = try read("scripts/build-app.sh")
        XCTAssertTrue(script.contains("Contents/Frameworks/SentryWithoutUIKit.framework"), "Sentry isn't embedded")
        XCTAssertTrue(script.contains(#""${SIGN[@]}" "$APP/Contents/Frameworks/SentryWithoutUIKit.framework""#), "Sentry isn't signed")
    }

    /// Sentry is MIT-licensed, so its notice travels with the app.
    func testSentryIsCredited() throws {
        let notices = try read("THIRD_PARTY_NOTICES.md")
        XCTAssertTrue(notices.contains("[Sentry](https://github.com/getsentry/sentry-cocoa)"), "no Sentry row in the table")
        XCTAssertTrue(notices.contains("**Sentry:**"), "no Sentry copyright entry")
    }
}
