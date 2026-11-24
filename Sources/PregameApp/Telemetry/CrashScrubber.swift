import Foundation
import SentryWithoutUIKit

/// Removes what could identify the Mix Host or their music from a crash report
/// before Sentry sends it (docs/privacy.md): paths and file names in any text,
/// where the app and its source lived, the Mac's name, the user and breadcrumbs.
/// It errs towards removing too much: a crash is read from its stack, not its text.
enum CrashScrubber {
    /// A path (absolute, home-relative or a file URL) up to the next colon,
    /// quote, bracket or line end; paths can contain spaces.
    private static let path = try! NSRegularExpression(
        pattern: #"(?:file://|~(?=/)|(?<=^|[\s"“‘'(\[=<]))/[^:\n"“”‘’()\[\]<>]*"#)
    /// A song, Mix or playlist file name, from the last quote, bracket, slash or
    /// colon (or the start) to its extension.
    private static let fileName = try! NSRegularExpression(
        pattern: #"(?<=^|[\n"“‘(\[/:<]|:\s)[^\n"“”‘’()\[\]/:<>]*?\.(?:mp3|wav|wave|aiff?|flac|m4a|aac|alac|ogg|oga|opus|wma|mp4|caf|hmix|m3u8?|csv|cue)\b"#,
        options: .caseInsensitive)

    /// The text with every path replaced by `<path>` and file name by `<file>`.
    static func scrub(_ text: String) -> String {
        var s = text
        for (regex, token) in [(path, "<path>"), (fileName, "<file>")] {
            s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: token)
        }
        return s
    }

    static func scrub(_ event: Event) -> Event? {
        event.serverName = nil
        event.user = nil
        event.breadcrumbs = nil
        event.request = nil
        if let m = event.message { event.message = SentryMessage(formatted: scrub(m.formatted)) }
        for e in event.exceptions ?? [] {
            e.value = e.value.map(scrub)
            e.mechanism?.desc = e.mechanism?.desc.map(scrub)
            scrub(e.stacktrace)
        }
        for t in event.threads ?? [] {
            t.name = t.name.map(scrub)
            scrub(t.stacktrace)
        }
        scrub(event.stacktrace)
        for image in event.debugMeta ?? [] { image.codeFile = image.codeFile.map(lastComponent) }
        event.context = event.context.map { context in
            var c = context
            c["device"]?["name"] = nil
            return c.mapValues { $0.mapValues(scrubValue) }
        }
        event.extra = event.extra?.mapValues(scrubValue)
        event.tags = event.tags?.mapValues(scrub)
        return event
    }

    private static func scrub(_ stack: SentryStacktrace?) {
        for f in stack?.frames ?? [] {
            f.package = f.package.map(lastComponent)
            f.fileName = f.fileName.map(lastComponent)
            f.contextLine = nil
            f.preContext = nil
            f.postContext = nil
            f.vars = nil
        }
    }

    private static func scrubValue(_ value: Any) -> Any {
        switch value {
        case let s as String: scrub(s)
        case let a as [Any]: a.map(scrubValue)
        case let d as [String: Any]: d.mapValues(scrubValue)
        default: value
        }
    }

    private static func lastComponent(_ path: String) -> String { (path as NSString).lastPathComponent }
}
