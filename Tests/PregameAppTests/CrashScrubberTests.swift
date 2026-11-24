import Foundation
import SentryWithoutUIKit
import XCTest
@testable import PregameApp

/// Crash reports leave the Mac without file names, paths, the Mac's name or a
/// user (docs/privacy.md). Sentry hands every event to the scrubber before
/// sending it.
final class CrashScrubberTests: XCTestCase {
    private func frame(_ package: String, file: String? = nil) -> Frame {
        let f = Frame()
        f.package = package
        f.fileName = file
        f.function = "MixEngine.render(into:)"
        return f
    }

    private func crash() -> Event {
        let e = Event(level: .fatal)
        e.serverName = "Praful’s MacBook Pro"
        e.user = User(userId: "abc")
        e.message = SentryMessage(formatted: "Couldn't decode /Users/praful/Music/Party/01 Daft Punk - One More Time.mp3")
        let exception = Exception(value: "Can’t open file:///Volumes/USB/Sets/Friday.hmix: denied", type: "NSInvalidArgumentException")
        let stack = SentryStacktrace(frames: [
            frame("/Users/praful/Downloads/Pregame.app/Contents/MacOS/Pregame", file: "/Users/runner/work/pregame/Sources/PregameCore/MixEngine.swift"),
            frame("/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit"),
        ], registers: [:])
        exception.stacktrace = stack
        e.exceptions = [exception]
        let thread = SentryThread(threadId: 0)
        thread.name = "Analysing “Big Night Out.flac”"
        thread.stacktrace = stack
        e.threads = [thread]
        let image = DebugMeta()
        image.codeFile = "/Users/praful/Downloads/Pregame.app/Contents/MacOS/Pregame"
        image.debugID = "D0E1F2"
        e.debugMeta = [image]
        e.context = ["device": ["model": "Mac16,10", "name": "Praful’s MacBook Pro"],
                     "app": ["app_name": "Pregame", "note": "saved to ~/Music/mix.wav"]]
        e.extra = ["track": "/Users/praful/Music/a.m4a"]
        e.tags = ["file": "Song Title.aiff"]
        e.breadcrumbs = [Breadcrumb(level: .info, category: "ui")]
        return e
    }

    private func scrubbed() throws -> Event { try XCTUnwrap(CrashScrubber.scrub(crash())) }

    func testPathsAndFileNamesAreRemovedFromMessages() throws {
        let e = try scrubbed()
        XCTAssertEqual(e.message?.formatted, "Couldn't decode <path>")
        XCTAssertEqual(e.exceptions?.first?.value, "Can’t open <path>: denied")
        XCTAssertEqual(e.exceptions?.first?.type, "NSInvalidArgumentException")
        XCTAssertEqual(e.threads?.first?.name, "Analysing “<file>”")
        XCTAssertEqual(e.extra?["track"] as? String, "<path>")
        XCTAssertEqual(e.tags?["file"], "<file>")
        XCTAssertEqual(e.context?["app"]?["note"] as? String, "saved to <path>")
        XCTAssertEqual(e.context?["app"]?["app_name"] as? String, "Pregame")
    }

    /// Frames keep the binary's name and the function, which is what a crash
    /// needs to be read, but not where the app or the source lived.
    func testStackFramesKeepOnlyTheBinarysName() throws {
        let e = try scrubbed()
        for frames in [e.exceptions?.first?.stacktrace?.frames, e.threads?.first?.stacktrace?.frames] {
            XCTAssertEqual(frames?.map(\.package), ["Pregame", "AppKit"])
            XCTAssertEqual(frames?.first?.fileName, "MixEngine.swift")
            XCTAssertEqual(frames?.first?.function, "MixEngine.render(into:)")
        }
        XCTAssertEqual(e.debugMeta?.first?.codeFile, "Pregame")
        XCTAssertEqual(e.debugMeta?.first?.debugID, "D0E1F2", "symbolication needs the image's ID")
    }

    func testTheMacsNameTheUserAndBreadcrumbsAreDropped() throws {
        let e = try scrubbed()
        XCTAssertNil(e.serverName)
        XCTAssertNil(e.user)
        XCTAssertNil(e.context?["device"]?["name"])
        XCTAssertEqual(e.context?["device"]?["model"] as? String, "Mac16,10")
        XCTAssertTrue(e.breadcrumbs?.isEmpty ?? true)
    }

    func testTextWithoutPathsIsLeftAlone() {
        XCTAssertEqual(CrashScrubber.scrub("Index out of range"), "Index out of range")
        XCTAssertEqual(CrashScrubber.scrub("Fatal error: 3/4 done"), "Fatal error: 3/4 done")
    }
}
