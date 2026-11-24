import Foundation
import XCTest
@testable import PregameApp
@testable import PregameCore

/// Pregame runs in the App Sandbox (ADR-0003). These check the entitlements the
/// app is signed with (scripts/Pregame.entitlements, applied by build-app.sh).
final class SandboxTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func entitlements() throws -> [String: Any] {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("scripts/Pregame.entitlements"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    /// Sandboxed, reading and writing what the user picks, and keeping
    /// bookmarks to it; plus the library exception the self-signed hardened
    /// runtime needs (docs/signing.md) and the Mach services Sparkle installs
    /// updates through (docs/updates.md, UpdateTests); and outgoing network
    /// connections, for crash reports and usage data the Mix Host agreed to
    /// (docs/privacy.md, TelemetryTests). Nothing else: no incoming
    /// connections, no devices.
    func testTheAppIsSandboxedWithOnlyWhatItNeeds() throws {
        let e = try entitlements()
        XCTAssertEqual(Set(e.keys), [
            "com.apple.security.app-sandbox",
            "com.apple.security.files.user-selected.read-write",
            "com.apple.security.files.bookmarks.app-scope",
            "com.apple.security.temporary-exception.files.home-relative-path.read-only",
            "com.apple.security.temporary-exception.mach-lookup.global-name",
            "com.apple.security.cs.disable-library-validation",
            "com.apple.security.network.client",
        ])
        for key in e.keys where !key.contains("temporary-exception") {
            XCTAssertEqual(e[key] as? Bool, true, key)
        }
    }

    /// The only file access outside the container is read-only, to exactly the data and
    /// settings from before the sandbox that get copied in at launch.
    func testTheOnlyExceptionIsReadingTheDataFromBeforeTheSandbox() throws {
        let paths = try XCTUnwrap(try entitlements()["com.apple.security.temporary-exception.files.home-relative-path.read-only"] as? [String])
        let expected = [DataFolders.legacyApplicationSupport] + LegacyDefaults.files
        XCTAssertEqual(Set(paths.map { "~" + $0 }),
                       Set(expected.map { DataFolders.displayPath($0) + ($0.hasDirectoryPath ? "/" : "") }))
    }
}
