import Observation
import SwiftUI

struct SettingsView: View {
  @Bindable var settings: SettingsStore
  @Bindable var store: TeleportNodeStore

  var body: some View {
    Form {
      Section("Teleport") {
        TextField("Proxy override", text: $settings.proxyAddress, prompt: Text("teleport.example.com:443"))
        TextField("Grouping label", text: $settings.groupingLabelKey, prompt: Text("customer"))
        TextField("Login label", text: $settings.loginLabelKey, prompt: Text("user"))
        TextField("Fallback login", text: $settings.fallbackLogin, prompt: Text("ubuntu"))
      }

      Section("External Terminal") {
        Picker("Terminal application", selection: $settings.terminalApplicationID) {
          ForEach(terminalApplications) { terminalApplication in
            Text(terminalTitle(for: terminalApplication))
              .tag(terminalApplication.rawValue)
          }
        }
        .pickerStyle(.menu)
      }

      Section("Embedded Terminal") {
        TextField(
          "Scrollback lines",
          value: $settings.terminalScrollbackLines,
          format: .number
        )

        Text("Set to 0 to disable scrollback.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Sound Feedback") {
        Toggle("Play sounds for app actions", isOn: $settings.soundFeedbackEnabled)

        HStack {
          Image(systemName: "speaker.fill")
            .foregroundStyle(.secondary)

          Slider(value: $settings.soundFeedbackVolume, in: 0...1)
            .disabled(!settings.soundFeedbackEnabled)

          Image(systemName: "speaker.wave.3.fill")
            .foregroundStyle(.secondary)

          Text(settings.soundFeedbackVolume, format: .percent.precision(.fractionLength(0)))
            .monospacedDigit()
            .frame(width: 42, alignment: .trailing)
        }

        Button("Preview sound") {
          SoundFeedbackService.play(.completed, settings: settings)
        }
        .disabled(!settings.soundFeedbackEnabled || settings.soundFeedbackVolume == 0)
      }

      Section("Server Cache") {
        Button("Refresh server cache") {
          Task {
            await store.refresh(using: settings, forceRefresh: true)
          }
        }
        .disabled(store.isLoading)

        if let lastRefreshedAt = store.lastRefreshedAt {
          Text("Cached servers updated \(lastRefreshedAt.formatted(date: .abbreviated, time: .shortened)).")
        } else {
          Text("Servers will be cached after the first successful fetch.")
        }
      }

      Section("Behavior") {
        Text("Leave proxy empty to reuse the active tsh profile.")
        Text("Leave grouping label empty to show a flat list.")
        Text("The login label is checked first. If it is missing or invalid, the app falls back to the manual login or the first active tsh login.")
        Text("The desktop app uses an embedded shell by default. External terminal settings are only used when you choose to open a session outside the app.")
        Text("Server lists are reused from local cache until you force a refresh.")
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .formStyle(.grouped)
  }

  private var terminalApplications: [TerminalApplication] {
    var applications = TerminalApplication.selectableApplications
    let selectedApplication = settings.selectedTerminalApplication

    if !applications.contains(selectedApplication) {
      applications.append(selectedApplication)
    }

    return applications
  }

  private func terminalTitle(for terminalApplication: TerminalApplication) -> String {
    if terminalApplication != .systemDefault && !terminalApplication.isInstalled {
      return "\(terminalApplication.displayName) (not installed)"
    }

    return terminalApplication.displayName
  }
}
