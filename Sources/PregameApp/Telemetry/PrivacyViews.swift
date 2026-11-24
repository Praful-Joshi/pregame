import SwiftUI

/// Where docs/privacy.md is published: the list of everything that's sent.
let privacyDocURL = URL(string: "https://github.com/Praful-Joshi/pregame/blob/main/docs/privacy.md")!

/// The one-time question on first launch (docs/design.md): what to share,
/// then "No thanks" or "Share selected", plain buttons of equal weight with no
/// default, so neither Return nor Esc answers it.
struct ConsentPrompt: View {
    @ObservedObject private var telemetry = Telemetry.shared
    @Environment(\.dismiss) private var dismiss
    @State private var crashReports = true
    @State private var usageData = true

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Label("Help make Pregame better?", systemImage: "hand.raised")
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: Space.m) {
                if telemetry.canReportCrashes {
                    Toggle("Send crash reports", isOn: $crashReports)
                }
                if telemetry.canSendUsage {
                    Toggle("Send anonymous usage data, like “Mix created” or “export finished”", isOn: $usageData)
                }
            }
            .toggleStyle(.checkbox)
            Text("Never your music, Track titles, file names or paths. Each comes with the app version and the kind of Mac.")
                .foregroundStyle(.secondary)
            Link("See everything that's sent", destination: privacyDocURL)
            Text("You can change this anytime in Settings › Privacy.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: Space.l) {
                Button { answer(share: false) } label: { Text("No thanks").frame(maxWidth: .infinity) }
                Button { answer(share: true) } label: { Text("Share selected").frame(maxWidth: .infinity) }
                    .disabled(!(crashReports && telemetry.canReportCrashes) && !(usageData && telemetry.canSendUsage))
            }
            .controlSize(.large)
        }
        .padding(Space.xxl)
        .frame(width: 440)
        .interactiveDismissDisabled()
    }

    private func answer(share: Bool) {
        telemetry.answer(crashReports: share && crashReports, usageData: share && usageData)
        dismiss()
    }
}

/// Settings › Privacy: each choice on its own.
struct PrivacySettings: View {
    @ObservedObject private var telemetry = Telemetry.shared

    var body: some View {
        Form {
            Section {
                Toggle("Send crash reports", isOn: $telemetry.crashReports)
                    .disabled(!telemetry.canReportCrashes)
                Toggle("Send anonymous usage data", isOn: $telemetry.usageData)
                    .disabled(!telemetry.canSendUsage)
            } footer: {
                Text(telemetry.isAvailable
                     ? "Crash reports go to Sentry and usage data to TelemetryDeck. Neither includes your music, Track titles, file names or paths."
                     : "This build has nothing to send to: only release builds carry the crash and usage keys.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Link("See everything that's sent", destination: privacyDocURL)
            }
        }
        .formStyle(.grouped)
    }
}
