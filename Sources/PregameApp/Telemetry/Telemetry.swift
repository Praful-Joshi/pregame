import CryptoKit
import Foundation

/// Something that reports crashes once started (Sentry, `CrashReports`).
protocol CrashReporting: AnyObject {
    func start()
    func stop()
}

/// Opt-in crash reports and usage data (docs/privacy.md). Nothing is started
/// or sent until the Mix Host agrees, and each can be turned off in Settings.
final class Telemetry: ObservableObject {
    /// What every usage event carries: the app's version and the machine class.
    struct Context: Equatable {
        var appVersion: String
        var buildNumber: String
        var chip: String
        var memoryGB: Int
    }

    private let defaults: UserDefaults
    private let usageAppID: String?
    private let crashReporter: CrashReporting?
    private let context: Context
    private let send: @Sendable (URLRequest) async -> Void

    init(defaults: UserDefaults, usageAppID: String?, crashReporter: CrashReporting?,
         context: Context, send: @escaping @Sendable (URLRequest) async -> Void) {
        self.defaults = defaults
        self.usageAppID = usageAppID
        self.crashReporter = crashReporter
        self.context = context
        self.send = send
    }

    private enum Key {
        static let asked = "telemetry.asked"
        static let crashReports = "telemetry.crashReports"
        static let usageData = "telemetry.usageData"
        static let installID = "telemetry.installID"
    }

    private let sessionID = UUID().uuidString
    private let installIDLock = NSLock()

    /// Whether this build can send anything at all: release builds carry the
    /// Sentry DSN and TelemetryDeck app ID in Info.plist.
    var isAvailable: Bool { canReportCrashes || canSendUsage }
    var canReportCrashes: Bool { crashReporter != nil }
    var canSendUsage: Bool { usageAppID != nil }

    /// The one-time prompt hasn't been answered yet.
    var needsAnswer: Bool { isAvailable && !defaults.bool(forKey: Key.asked) }

    private var promptClaimed = false

    /// True for the first window to ask while the prompt is unanswered, so
    /// several Mix windows opening at launch don't all ask.
    func claimPrompt() -> Bool {
        guard needsAnswer, !promptClaimed else { return false }
        promptClaimed = true
        return true
    }

    /// The prompt's answer: one choice for both, each changeable in Settings later.
    func answer(share: Bool) {
        defaults.set(true, forKey: Key.asked)
        crashReports = share
        usageData = share
    }

    var crashReports: Bool {
        get { crashReporter != nil && defaults.bool(forKey: Key.crashReports) }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Key.crashReports)
            if crashReports { crashReporter?.start() } else { crashReporter?.stop() }
        }
    }

    var usageData: Bool {
        get { usageAppID != nil && defaults.bool(forKey: Key.usageData) }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Key.usageData)
        }
    }

    /// At launch: starts crash reporting if the Mix Host agreed to it.
    func start() {
        if crashReports { crashReporter?.start() }
    }

    /// Sends the event if the Mix Host agreed to share usage data; otherwise
    /// drops it. Safe to call from any thread.
    func record(_ event: TelemetryEvent) {
        guard usageData, let appID = usageAppID else { return }
        let request = UsageSignal(appID: appID, clientUser: hashedInstallID, sessionID: sessionID,
                                  event: event, context: context).request()
        let send = send
        Task { await send(request) }
    }

    /// A random ID for this install, created the first time an event is sent
    /// and only ever sent hashed (TelemetryDeck hashes it again with a salt).
    private var hashedInstallID: String {
        // Analysis records from background tasks: create the ID only once.
        installIDLock.lock(); defer { installIDLock.unlock() }
        let id = defaults.string(forKey: Key.installID) ?? {
            let new = UUID().uuidString
            defaults.set(new, forKey: Key.installID)
            return new
        }()
        return SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// One TelemetryDeck signal, as its ingest API (v2) takes it.
struct UsageSignal: Encodable {
    static let endpoint = URL(string: "https://nom.telemetrydeck.com/v2/")!

    let appID: String
    let clientUser: String
    let sessionID: String
    let type: String
    let payload: [String: String]
    let floatValue: Double?
    let receivedAt: String
    let isTestMode: String

    init(appID: String, clientUser: String, sessionID: String, event: TelemetryEvent,
         context: Telemetry.Context, date: Date = Date()) {
        self.appID = appID
        self.clientUser = clientUser
        self.sessionID = sessionID
        type = event.name
        payload = event.fields.merging([
            "appVersion": context.appVersion,
            "buildNumber": context.buildNumber,
            "chip": context.chip,
            "memoryGB": "\(context.memoryGB)",
        ]) { own, _ in own }
        floatValue = event.value
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        receivedAt = f.string(from: date)
        #if DEBUG
        isTestMode = "true"   // shown apart from real users' data in TelemetryDeck
        #else
        isTestMode = "false"
        #endif
    }

    func request() -> URLRequest {
        var r = URLRequest(url: Self.endpoint)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONEncoder().encode([self])
        return r
    }
}

extension Telemetry {
    /// The app's instance. The Sentry DSN and TelemetryDeck app ID come from
    /// Info.plist (docs/privacy.md); a build without them asks nothing and
    /// sends nothing.
    static let shared: Telemetry = {
        let info = Bundle.main.infoDictionary ?? [:]
        func setting(_ key: String) -> String? {
            (info[key] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        }
        let context = Context.current
        return Telemetry(
            defaults: .standard,
            usageAppID: setting("PregameTelemetryDeckAppID"),
            crashReporter: setting("PregameSentryDSN").map {
                SentryCrashReporter(dsn: $0, release: "pregame@\(context.appVersion)+\(context.buildNumber)")
            },
            context: context,
            send: { request in _ = try? await URLSession.shared.data(for: request) })
    }()
}

extension Telemetry.Context {
    /// This app and Mac: the version, the chip (say "M4 Pro") and the memory
    /// rounded to whole gigabytes.
    static var current: Self {
        let info = Bundle.main.infoDictionary ?? [:]
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        let chip = String(cString: brand).replacingOccurrences(of: "Apple ", with: "")
        return Self(appVersion: info["CFBundleShortVersionString"] as? String ?? "dev",
                    buildNumber: info["CFBundleVersion"] as? String ?? "0",
                    chip: chip.isEmpty ? "unknown" : chip,
                    memoryGB: Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded()))
    }
}
