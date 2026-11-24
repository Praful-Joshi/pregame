import Foundation
import XCTest

/// Tagging a version builds, signs and packages the DMG, signs the appcast and
/// publishes a GitHub Release, but only after the maintainer approves the
/// protected `release` environment (docs/releasing.md). CI rehearses the whole
/// pipeline with throwaway keys; these check the rules it must keep.
final class ReleaseTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func text(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
    }

    private func run(_ executable: String, _ arguments: [String] = [],
                     environment: [String: String] = [:]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func script(_ name: String) -> String {
        Self.root.appendingPathComponent("scripts/\(name)").path
    }

    private func workflows() throws -> [(name: String, text: String)] {
        let folder = Self.root.appendingPathComponent(".github/workflows")
        return try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".yml") || $0.hasSuffix(".yaml") }
            .sorted()
            .map { ($0, try String(contentsOf: folder.appendingPathComponent($0), encoding: .utf8)) }
    }

    /// The lines between `key:` at the start of a line and the next top-level key.
    private func topLevelBlock(_ key: String, in yaml: String) -> String {
        var lines: [Substring] = []
        var inside = false
        for line in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("\(key):") { inside = true; continue }
            if inside, let first = line.first, first != " ", first != "#" { break }
            if inside { lines.append(line) }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - The workflow

    /// Only a pushed version tag starts a release; a pull request never can.
    func testTheReleaseRunsOnVersionTagsOnly() throws {
        let release = try text(".github/workflows/release.yml")
        let triggers = topLevelBlock("on", in: release)
        XCTAssertTrue(triggers.contains("tags: [\"v*\"]"), triggers)
        for other in ["pull_request", "pull_request_target", "workflow_dispatch", "workflow_run", "schedule", "branches"] {
            XCTAssertFalse(triggers.contains(other), "the release also runs on \(other)")
        }
    }

    /// The job waits for the maintainer's approval in the `release` environment,
    /// which alone holds the signing certificate and the update key.
    func testTheReleaseRunsInTheProtectedEnvironment() throws {
        let release = try text(".github/workflows/release.yml")
        XCTAssertTrue(release.contains("\n    environment: release\n"), "the release job isn't in the release environment")
        for secret in ["PREGAME_SIGNING_P12", "PREGAME_SIGNING_P12_PASSPHRASE", "PREGAME_SPARKLE_KEY", "SENTRY_AUTH_TOKEN"] {
            XCTAssertTrue(release.contains("secrets.\(secret) }}"), "the release doesn't use \(secret)")
        }
    }

    /// No other workflow can read a secret, so nothing that runs for a pull
    /// request ever sees one.
    func testOnlyTheReleaseWorkflowUsesSecrets() throws {
        for workflow in try workflows() where workflow.name != "release.yml" {
            XCTAssertFalse(workflow.text.contains("secrets."), "\(workflow.name) reads a secret")
        }
    }

    /// A moved tag can't change what runs: every third-party action is pinned
    /// to a full commit SHA.
    func testEveryActionIsPinnedToACommit() throws {
        let uses = try NSRegularExpression(pattern: #"^\s*-?\s*uses:\s*(\S+)"#, options: .anchorsMatchLines)
        let pinned = try NSRegularExpression(pattern: #"^[\w.-]+/[\w./-]+@[0-9a-f]{40}$"#)
        var count = 0
        for workflow in try workflows() {
            let text = workflow.text as NSString
            for match in uses.matches(in: workflow.text, range: NSRange(location: 0, length: text.length)) {
                let action = text.substring(with: match.range(at: 1))
                count += 1
                if action.hasPrefix("./") { continue }   // a local action is in the same commit
                XCTAssertNotNil(pinned.firstMatch(in: action, range: NSRange(location: 0, length: (action as NSString).length)),
                                "\(workflow.name): \(action) isn't pinned to a commit SHA")
            }
        }
        XCTAssertGreaterThan(count, 0)
    }

    /// The release publishes the DMG and its appcast together, with a
    /// build-provenance attestation for both.
    func testTheReleasePublishesTheDMGAndAppcastWithProvenance() throws {
        let release = try text(".github/workflows/release.yml")
        XCTAssertTrue(release.contains("actions/attest-build-provenance@"), "no build-provenance attestation")
        XCTAssertTrue(release.contains("id-token: write") && release.contains("attestations: write"))
        XCTAssertTrue(release.contains("gh release create"), "nothing is published")
        XCTAssertTrue(release.contains("\"$DMG\" \"$APPCAST\""), "the release doesn't carry both the DMG and the appcast")
        XCTAssertTrue(release.contains("scripts/release.sh"), "the release doesn't build with scripts/release.sh")
        XCTAssertTrue(release.contains("scripts/make-appcast.sh"), "the appcast isn't generated")
    }

    /// Crash reports name Pregame's own functions only if Sentry has the
    /// release's debug symbols: build-app.sh writes a dSYM next to the app, and
    /// the release uploads it with a Sentry CLI whose download is pinned to a
    /// checksum (docs/privacy.md, docs/releasing.md).
    func testTheReleaseUploadsItsDebugSymbolsToSentry() throws {
        let build = try text("scripts/build-app.sh")
        XCTAssertTrue(build.contains("dsymutil") && build.contains("build/Pregame.dSYM"), "build-app.sh makes no dSYM")
        let release = try text(".github/workflows/release.yml")
        XCTAssertTrue(release.contains("debug-files upload"), "nothing is uploaded to Sentry")
        XCTAssertTrue(release.contains("build/Pregame.dSYM"), "the upload isn't the release's dSYM")
        XCTAssertTrue(release.contains("SENTRY_ORG: pregame-inc") && release.contains("SENTRY_PROJECT: pregame"))
        XCTAssertNotNil(release.range(of: #"[0-9a-f]{64}  sentry"#, options: .regularExpression)
                        .flatMap { _ in release.range(of: "shasum -a 256 -c") },
                        "the Sentry CLI download isn't checked against a pinned SHA-256")
    }

    /// Homebrew's libraries carry the minimum macOS of the machine that built
    /// them, so the release builds on the minimum macOS, as does its rehearsal.
    func testTheReleaseAndItsRehearsalBuildOnTheMinimumMacOS() throws {
        XCTAssertTrue(try text(".github/workflows/release.yml").contains("runs-on: macos-15"))
        let ci = try text(".github/workflows/ci.yml")
        let rehearsal = try XCTUnwrap(ci.range(of: "  release-rehearsal:"), "CI doesn't rehearse the release")
        XCTAssertTrue(ci[rehearsal.upperBound...].contains("runs-on: macos-15"))
        XCTAssertTrue(ci[rehearsal.upperBound...].contains("scripts/release.sh"))
    }

    // MARK: - Pinned sources

    /// TagLib, the one library bundled as a dylib, is built from a pinned and
    /// checksummed source release for the app's minimum macOS.
    func testTagLibIsBuiltFromAPinnedSource() throws {
        let build = try text("scripts/build-taglib.sh")
        XCTAssertNotNil(build.range(of: #"TAGLIB_VERSION="\d+\.\d+(\.\d+)?""#, options: .regularExpression), "no pinned version")
        XCTAssertNotNil(build.range(of: #"TAGLIB_SHA256="[0-9a-f]{64}""#, options: .regularExpression), "no pinned checksum")
        XCTAssertTrue(build.contains("CMAKE_OSX_DEPLOYMENT_TARGET"), "TagLib isn't built for the minimum macOS")
        XCTAssertTrue(try text("scripts/release.sh").contains("scripts/build-taglib.sh"), "the release doesn't build TagLib")
        XCTAssertTrue(try text("Package.swift").contains("PREGAME_TAGLIB_PREFIX"), "the package can't link the built TagLib")
    }

    /// The Demucs model is downloaded for the release and must match its pinned
    /// checksums; a file that doesn't is rejected, not shipped.
    func testAModelThatDoesntMatchItsChecksumIsRejected() throws {
        let models = FileManager.default.temporaryDirectory.appendingPathComponent("models-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: models) }
        try Data("not the model".utf8).write(to: models.appendingPathComponent("htdemucs.onnx"))
        try Data("not the weights".utf8).write(to: models.appendingPathComponent("htdemucs.onnx.data"))

        let result = try run(script("fetch-vendor.sh"), ["--model"], environment: ["PREGAME_MODELS_DIR": models.path])
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("htdemucs.onnx"), result.output)
        XCTAssertTrue(result.output.contains("doesn't match"), result.output)
        XCTAssertTrue(try text("scripts/release.sh").contains("scripts/fetch-vendor.sh --model"), "the release doesn't verify the model")
    }

    // MARK: - Checking the build

    /// Every Mach-O in the app, and every object in a static library linked
    /// into it, must run on the minimum macOS: code built for a newer macOS is
    /// reported by name, code built for the minimum passes.
    func testCodeBuiltForANewerMacOSIsCaught() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("minos-\(UUID().uuidString)")
        let frameworks = work.appendingPathComponent("Pregame.app/Contents/Frameworks")
        try FileManager.default.createDirectory(at: frameworks, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let source = work.appendingPathComponent("lib.c")
        try Data("int answer(void) { return 42; }\n".utf8).write(to: source)
        try Data("not code\n".utf8).write(to: frameworks.appendingPathComponent("README"))

        func compile(_ output: URL, minimum: String, _ kind: String) throws {
            let built = try run("/usr/bin/xcrun", ["clang", kind, "-arch", "arm64", "-mmacosx-version-min=\(minimum)",
                                                   source.path, "-o", output.path])
            XCTAssertEqual(built.status, 0, built.output)
        }
        func archive(_ name: String, minimum: String) throws -> String {
            let object = work.appendingPathComponent("\(name).o")
            try compile(object, minimum: minimum, "-c")
            let library = work.appendingPathComponent("\(name).a")
            let archived = try run("/usr/bin/xcrun", ["libtool", "-static", "-o", library.path, object.path])
            XCTAssertEqual(archived.status, 0, archived.output)
            return library.path
        }
        let app = work.appendingPathComponent("Pregame.app").path

        try compile(frameworks.appendingPathComponent("libfine.dylib"), minimum: "15.0", "-dynamiclib")
        let fineStatic = try archive("libfinestatic", minimum: "15.0")
        let fine = try run(script("check-min-macos.sh"), ["--minimum", "15.0", app, fineStatic])
        XCTAssertEqual(fine.status, 0, fine.output)

        try compile(frameworks.appendingPathComponent("libnewer.dylib"), minimum: "26.0", "-dynamiclib")
        let newer = try run(script("check-min-macos.sh"), ["--minimum", "15.0", app])
        XCTAssertNotEqual(newer.status, 0, newer.output)
        XCTAssertTrue(newer.output.contains("Contents/Frameworks/libnewer.dylib: needs macOS 26.0"), newer.output)
        XCTAssertFalse(newer.output.contains("libfine.dylib: needs"), newer.output)

        let newerStatic = try archive("libnewerstatic", minimum: "26.0")
        let linked = try run(script("check-min-macos.sh"), ["--minimum", "15.0", fineStatic, newerStatic])
        XCTAssertNotEqual(linked.status, 0, linked.output)
        XCTAssertTrue(linked.output.contains("libnewerstatic.a(libnewerstatic.o): needs macOS 26.0"), linked.output)
        XCTAssertFalse(linked.output.contains("libfinestatic.a"), linked.output)
    }

    /// The tag names the version: a tag that doesn't match the app's version
    /// stops the release before anything is built.
    func testATagThatDoesntMatchTheVersionStopsTheRelease() throws {
        let result = try run(script("release.sh"), ["v999.0"])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("CFBundleShortVersionString"), result.output)
        XCTAssertFalse(result.output.contains("Compiling"), "checked the tag only after building")
        XCTAssertFalse(result.output.contains("Downloading"), "checked the tag only after downloading")
    }

    /// The maintainer has written steps to back up and rotate both keys.
    func testKeyBackupAndRotationAreDocumented() throws {
        let doc = try text("docs/releasing.md")
        for heading in ["## Back up the keys", "## Rotating the update key", "## Rotating the signing certificate"] {
            XCTAssertTrue(doc.contains(heading), "docs/releasing.md has no \"\(heading)\"")
        }
    }
}
