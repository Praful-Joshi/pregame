import Foundation
import SentryWithoutUIKit

/// Crash reports through Sentry, started only once the Mix Host agrees
/// (Telemetry). Until `start()`, the SDK isn't running and sends nothing.
/// Everything but crashes and app hangs is off, and every report goes
/// through CrashScrubber first.
final class SentryCrashReporter: CrashReporting {
    private let dsn: String
    private let release: String

    init(dsn: String, release: String) {
        self.dsn = dsn
        self.release = release
    }

    func start() {
        guard !SentrySDK.isEnabled else { return }
        SentrySDK.start { o in
            o.dsn = self.dsn
            o.releaseName = self.release
            #if DEBUG
            o.environment = "debug"
            #endif
            o.sendDefaultPii = false
            o.beforeSend = CrashScrubber.scrub
            o.beforeBreadcrumb = { _ in nil }
            o.maxBreadcrumbs = 0
            o.enableAutoBreadcrumbTracking = false
            o.enableNetworkBreadcrumbs = false
            o.enableAutoSessionTracking = false
            o.enableAutoPerformanceTracing = false
            o.enableNetworkTracking = false
            o.enableCaptureFailedRequests = false
            o.enableFileIOTracing = false
            o.enableDataSwizzling = false
            o.enableFileManagerSwizzling = false
            o.enableCoreDataTracing = false
            o.enableSwizzling = false
            o.enableMetricKit = false
            o.enableLogs = false
            o.enableMetrics = false
            o.tracesSampleRate = 0
        }
    }

    /// Stops reporting now. Reports already waiting on disk aren't sent while
    /// it's off, because the SDK only sends them after a start.
    func stop() {
        guard SentrySDK.isEnabled else { return }
        SentrySDK.close()
    }
}
