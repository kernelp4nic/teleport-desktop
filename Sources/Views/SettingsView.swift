import AppKit
import Observation
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
  case general
  case servers
  case terminal
  case sounds
  case about

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general: return "General"
    case .servers: return "Servers"
    case .terminal: return "Terminal"
    case .sounds: return "Sounds"
    case .about: return "About"
    }
  }

  var icon: String {
    switch self {
    case .general: return "gearshape"
    case .servers: return "server.rack"
    case .terminal: return "terminal"
    case .sounds: return "speaker.wave.2"
    case .about: return "info.circle"
    }
  }
}

struct SettingsView: View {
  @Bindable var settings: SettingsStore
  @Bindable var store: TeleportNodeStore
  @Bindable var library: NodeLibraryStore
  @State private var section: SettingsSection = .general
  @State private var onePasswordAccounts: [OnePasswordAccount] = []

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Divider()
      VStack(alignment: .leading, spacing: 24) {
        Text(section.title)
          .font(.system(size: 24, weight: .bold))

        ScrollView {
          VStack(alignment: .leading, spacing: 22) {
            page
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(1)
          .padding(.trailing, 12)
        }
      }
      .padding(28)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(nsColor: .windowBackgroundColor))
    }
    .frame(minWidth: 760, idealWidth: 820, minHeight: 520, idealHeight: 600)
  }

  private var sidebar: some View {
    VStack(spacing: 4) {
      ForEach(SettingsSection.allCases) { item in
        Button {
          section = item
        } label: {
          HStack(spacing: 12) {
            Image(systemName: item.icon)
              .font(.system(size: 17))
              .frame(width: 22)
            Text(item.title)
              .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 12)
          .frame(height: 42)
          .foregroundStyle(section == item ? Color.white : Color.primary)
          .background(section == item ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 8))
          .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(SidebarButtonStyle())
      }
      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.top, 24)
    .frame(width: 220)
    .background(.regularMaterial)
  }

  @ViewBuilder
  private var page: some View {
    switch section {
    case .general:
      card {
        Text("Teleport")
          .font(.headline)
        row("Proxy override", "Leave empty to reuse the active tsh profile.") {
          TextField("Proxy override", text: $settings.proxyAddress, prompt: Text("teleport.example.com:443"))
            .labelsHidden()
            .frame(width: 240)
        }
        Divider()
        row("Teleport user", "Passed to tsh login as --user. Leave empty to use your macOS user name.") {
          TextField("Teleport user", text: $settings.teleportUser, prompt: Text(NSUserName()))
            .labelsHidden()
            .frame(width: 240)
        }
      }
      card {
        Text("1Password")
          .font(.headline)
        toggle(
          "Fill login from 1Password",
          "Answers the tsh login password and OTP prompts using the 1Password CLI (op). Enable \"Integrate with 1Password CLI\" in 1Password's Developer settings to unlock with Touch ID.",
          $settings.onePasswordEnabled
        )
        Divider()
        row("Account", "Used when the 1Password CLI is signed in to more than one account.") {
          Picker("Account", selection: $settings.onePasswordAccount) {
            Text("Default").tag("")
            ForEach(onePasswordAccounts) { account in
              Text(account.displayName).tag(account.id)
            }
            if !settings.onePasswordAccount.isEmpty,
               !onePasswordAccounts.contains(where: { $0.id == settings.onePasswordAccount }) {
              Text(settings.onePasswordAccount).tag(settings.onePasswordAccount)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(width: 240)
        }
        .disabled(!settings.onePasswordEnabled)
        .task {
          onePasswordAccounts = await Task.detached {
            (try? OnePasswordService().listAccounts()) ?? []
          }.value
        }
        Divider()
        row("Item", "Name or ID of the login item. Its username is used when Teleport user is empty.") {
          TextField("Item", text: $settings.onePasswordItem, prompt: Text("Teleport"))
            .labelsHidden()
            .frame(width: 240)
        }
        .disabled(!settings.onePasswordEnabled)
        Divider()
        row("Vault", "Optional. Leave empty to search all vaults.") {
          TextField("Vault", text: $settings.onePasswordVault, prompt: Text("Private"))
            .labelsHidden()
            .frame(width: 240)
        }
        .disabled(!settings.onePasswordEnabled)
      }
      card {
        Text("Session")
          .font(.headline)
        row("Status", statusDescription) {
          Label(store.session.statusText, systemImage: store.session.isActive ? "checkmark.circle.fill" : "xmark.circle")
            .foregroundStyle(store.session.isActive ? .green : .secondary)
        }
      }

    case .servers:
      card {
        Text("Labels")
          .font(.headline)
        row("Grouping label", "Groups servers in the sidebar by this label. Leave empty to show a flat list.") {
          TextField("Grouping label", text: $settings.groupingLabelKey, prompt: Text("customer"))
            .labelsHidden()
            .frame(width: 180)
        }
        Divider()
        row("Login label", "Checked first to pick the SSH login for each server.") {
          TextField("Login label", text: $settings.loginLabelKey, prompt: Text("user"))
            .labelsHidden()
            .frame(width: 180)
        }
        Divider()
        row("Fallback login", "Used when the login label is missing or invalid. If empty, the first active tsh login is used.") {
          TextField("Fallback login", text: $settings.fallbackLogin, prompt: Text("ubuntu"))
            .labelsHidden()
            .frame(width: 180)
        }
      }
      card {
        Text("Sidebar")
          .font(.headline)
        toggle(
          "Show recent servers",
          "Lists the servers you connected to most recently above the groups.",
          $settings.showsRecentServers
        )
      }
      if let groupingKey = settings.normalizedGroupingLabelKey {
        card {
          Text("Group Icons")
            .font(.headline)
          Text("Shown before each \(groupingKey) group in the sidebar. Enter an emoji (press ⌃⌘Space for the picker) or an SF Symbol name such as globe.americas.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

          if groupValues.isEmpty {
            Text("No groups loaded yet.")
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
          } else {
            ForEach(groupValues, id: \.self) { group in
              Divider()
              HStack(spacing: 12) {
                Text(group)
                  .font(.system(size: 13, weight: .medium))
                Spacer()
                TextField("Icon", text: groupIconBinding(for: group), prompt: Text(""))
                  .labelsHidden()
                  .frame(width: 180)
              }
            }
          }
        }
      }
      card {
        row("Server cache", cacheDescription) {
          Button("Refresh now") {
            Task {
              await store.refresh(using: settings, forceRefresh: true)
            }
          }
          .disabled(store.isLoading)
        }
      }

    case .terminal:
      card {
        Text("Embedded terminal")
          .font(.headline)
        toggle(
          "Local echo",
          "Predict typed characters before the server responds. Applies to SSH sessions.",
          $settings.localEchoEnabled
        )
        Divider()
        row("Scrollback lines", "Set to 0 to disable scrollback.") {
          TextField("Scrollback lines", value: $settings.terminalScrollbackLines, format: .number)
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: 100)
        }
      }
      card {
        Text("External terminal")
          .font(.headline)
        row("Terminal application", "Used only when you choose to open a session outside the app.") {
          Picker("Terminal application", selection: $settings.terminalApplicationID) {
            ForEach(terminalApplications) { terminalApplication in
              Text(terminalTitle(for: terminalApplication))
                .tag(terminalApplication.rawValue)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(width: 200)
        }
      }

    case .sounds:
      card {
        toggle("Sound feedback", "Play sounds for app actions like connecting or refreshing.", $settings.soundFeedbackEnabled)
        Divider()
        row("Volume", "") {
          HStack {
            Image(systemName: "speaker.fill")
              .foregroundStyle(.secondary)
            Slider(value: $settings.soundFeedbackVolume, in: 0...1)
              .frame(width: 180)
            Image(systemName: "speaker.wave.3.fill")
              .foregroundStyle(.secondary)
            Text(settings.soundFeedbackVolume, format: .percent.precision(.fractionLength(0)))
              .monospacedDigit()
              .frame(width: 42, alignment: .trailing)
          }
          .disabled(!settings.soundFeedbackEnabled)
        }
        Divider()
        row("Preview", "Play the completion sound at the current volume.") {
          Button("Play") {
            SoundFeedbackService.play(.completed, settings: settings)
          }
          .disabled(!settings.soundFeedbackEnabled || settings.soundFeedbackVolume == 0)
        }
      }

    case .about:
      VStack(spacing: 16) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .frame(width: 96, height: 96)
        Text("Teleport Desktop")
          .font(.system(size: 30, weight: .bold))
        Text("Version \(bundleValue("CFBundleShortVersionString") ?? "0.1.0") (\(bundleValue("CFBundleVersion") ?? "1"))")
          .foregroundStyle(.secondary)
        Text("A native Teleport client for macOS.")
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 20)
      card {
        row("Open source components", "SwiftTerm") {
          Button("Website") {
            if let url = URL(string: "https://github.com/migueldeicaza/SwiftTerm") {
              NSWorkspace.shared.open(url)
            }
          }
        }
      }
    }
  }

  private var statusDescription: String {
    var components: [String] = []

    if let username = store.session.username {
      components.append("Logged in as \(username)")
    }

    if let cluster = store.session.cluster {
      components.append(cluster)
    }

    if let validUntil = store.session.validUntil {
      components.append("valid until \(validUntil.formatted(date: .abbreviated, time: .shortened))")
    }

    return components.isEmpty ? "Run login from the main window to start a session." : components.joined(separator: " · ")
  }

  private var cacheDescription: String {
    if let lastRefreshedAt = store.lastRefreshedAt {
      return "Server lists are reused until you force a refresh. Updated \(lastRefreshedAt.formatted(date: .abbreviated, time: .shortened))."
    }

    return "Servers will be cached after the first successful fetch."
  }

  private func bundleValue(_ key: String) -> String? {
    Bundle.main.object(forInfoDictionaryKey: key) as? String
  }

  private var libraryScopeKey: String {
    library.scopeKey(session: store.session, settings: settings)
  }

  private var groupValues: [String] {
    guard let groupingKey = settings.normalizedGroupingLabelKey else {
      return []
    }

    return Array(Set(store.nodes.map { $0.groupValue(for: groupingKey) }))
      .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
  }

  private func groupIconBinding(for group: String) -> Binding<String> {
    Binding(
      get: { library.groupIcon(for: group, scopeKey: libraryScopeKey) ?? "" },
      set: { library.setGroupIcon($0, for: group, scopeKey: libraryScopeKey) }
    )
  }

  private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12, content: content)
      .padding(.horizontal, 16)
      .padding(.vertical, 16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.10)))
  }

  private func row<Control: View>(
    _ title: String,
    _ description: String,
    @ViewBuilder control: () -> Control
  ) -> some View {
    HStack(spacing: 20) {
      VStack(alignment: .leading, spacing: 5) {
        Text(title)
          .font(.system(size: 13, weight: .medium))
        if !description.isEmpty {
          Text(description)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 0)
      control()
    }
    .padding(.vertical, 2)
  }

  private func toggle(_ title: String, _ description: String, _ value: Binding<Bool>) -> some View {
    row(title, description) {
      Toggle(title, isOn: value)
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
    }
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

/// Plain sidebar button with a subtle highlight while hovered or pressed.
private struct SidebarButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    SidebarButtonBody(configuration: configuration)
  }
}

private struct SidebarButtonBody: View {
  let configuration: ButtonStyleConfiguration
  @State private var isHovered = false

  var body: some View {
    configuration.label
      .background(
        Color.primary.opacity(configuration.isPressed ? 0.12 : isHovered ? 0.06 : 0),
        in: RoundedRectangle(cornerRadius: 8)
      )
      .onHover { isHovered = $0 }
  }
}
