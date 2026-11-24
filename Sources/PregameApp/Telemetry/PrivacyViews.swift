import SwiftUI

/// Where docs/privacy.md is published: the list of everything that's sent.
let privacyDocURL = URL(string: "https://github.com/Praful-Joshi/pregame/blob/main/docs/privacy.md")!

/// The one-time question on first launch. Both answers carry equal weight:
/// neither is the default button, and Esc picks neither.
struct ConsentPrompt: View {
    @ObservedObject private var telemetry = Telemetry.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Label("Help make Pregame better?", systemImage: "hand.raised")
                .font(.title2.bold())
            Text("Pregame can send anonymous crash reports, and a few usage events like “Mix created” or “export finished”, with the app version and the kind of Mac.")
            Text("It never sends song titles, file names or paths, and never your music.")
                .foregroundStyle(.secondary)
            Link("See everything that's sent", destination: privacyDocURL)
            Text("You can change this anytime in Settings › Privacy.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: Space.l) {
                Button { choose(false) } label: { Text("No Thanks").frame(maxWidth: .infinity) }
                Button { choose(true) } label: { Text("Share").frame(maxWidth: .infinity) }
            }
            .controlSize(.large)
        }
        .padding(Space.xxl)
        .frame(width: 440)
        .interactiveDismissDisabled()
    }

    private func choose(_ share: Bool) {
        telemetry.answer(share: share)
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
                     ? "Crash reports go to Sentry and usage data to TelemetryDeck. Neither includes song titles, file names or paths."
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
