import SwiftUI

/// Runs `tsh login` in a small embedded terminal and closes itself as soon as
/// the store detects an active Teleport session. When 1Password autofill is
/// enabled, the password and OTP prompts are answered from the configured item.
struct TeleportLoginSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Bindable var store: TeleportNodeStore
  @Bindable var settings: SettingsStore
  @State private var terminalStore: TerminalSessionStore?
  @State private var phase: Phase = .running
  @State private var focusToken = 0
  @State private var credentials: OnePasswordCredentials?
  @State private var promptDetector = LoginPromptDetector()
  @State private var autofillMessage: String?
  @State private var autofillFailed = false

  private enum Phase: Equatable {
    case unlocking
    case running
    case verifying
    case failed(Int32?)
    case noSession
  }

  init(store: TeleportNodeStore, settings: SettingsStore) {
    self.store = store
    self.settings = settings

    // Without autofill, start right away; otherwise wait for 1Password so the
    // stored username can be passed to tsh login.
    if settings.onePasswordLoginItem == nil {
      _terminalStore = State(
        initialValue: TerminalSessionStore(
          windowState: DesktopWindowState.command(
            store.loginCommand(using: settings),
            title: "Teleport Login",
            summary: "Running tsh login"
          )
        )
      )
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "person.badge.key")
          .font(.title2)
          .foregroundStyle(.tint)

        VStack(alignment: .leading, spacing: 2) {
          Text("Teleport Login")
            .font(.headline)
          Text(loginCommand)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }

      Group {
        if let terminalStore {
          EmbeddedTerminalView(
            sessionStore: terminalStore,
            focusToken: focusToken,
            scrollbackLines: settings.terminalScrollbackLines,
            localEchoEnabled: false
          )
        } else {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(.quaternary, lineWidth: 1)
      )

      HStack(spacing: 8) {
        statusView

        Spacer()

        if phase != .running && phase != .verifying && phase != .unlocking {
          Button("Retry") {
            retry()
          }
        }

        Button("Cancel", role: .cancel) {
          close()
        }
        .keyboardShortcut(.cancelAction)
      }
    }
    .padding(20)
    .frame(width: 720, height: 460)
    .onAppear {
      if let terminalStore {
        configure(terminalStore)
        focusToken += 1
      } else {
        Task {
          await unlockAndStart()
        }
      }
    }
    .onDisappear {
      terminalStore?.terminalController.terminate()
    }
    .onChange(of: store.session.isActive) { _, isActive in
      if isActive {
        close()
      }
    }
  }

  @ViewBuilder
  private var statusView: some View {
    switch phase {
    case .unlocking:
      HStack(spacing: 6) {
        ProgressView()
          .controlSize(.small)
        Text("Reading credentials from 1Password…")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    case .running:
      if let autofillMessage {
        Label(autofillMessage, systemImage: autofillFailed ? "exclamationmark.triangle" : "key.fill")
          .font(.caption)
          .foregroundStyle(autofillFailed ? .orange : .secondary)
          .lineLimit(2)
      } else {
        Label("Waiting for login…", systemImage: "hourglass")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    case .verifying:
      HStack(spacing: 6) {
        ProgressView()
          .controlSize(.small)
        Text("Checking Teleport session…")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    case .failed(let exitCode):
      Label(
        exitCode.map { "tsh login exited with status \($0)" } ?? "tsh login was closed",
        systemImage: "exclamationmark.triangle"
      )
      .font(.caption)
      .foregroundStyle(.red)
    case .noSession:
      Label(
        "Login finished but no active session was detected",
        systemImage: "exclamationmark.triangle"
      )
      .font(.caption)
      .foregroundStyle(.red)
    }
  }

  private var loginCommand: String {
    store.loginCommand(using: settings, fallbackUser: credentials?.username)
  }

  private func configure(_ terminalStore: TerminalSessionStore) {
    terminalStore.terminalController.onProcessTerminated = { exitCode in
      processTerminated(exitCode: exitCode)
    }
    terminalStore.terminalController.onOutputText = { text in
      handleOutput(text)
    }
  }

  private func unlockAndStart() async {
    guard let item = settings.onePasswordLoginItem else {
      startLogin()
      return
    }

    phase = .unlocking
    let vault = settings.normalizedOnePasswordVault
    let account = settings.normalizedOnePasswordAccount
    let result = await Task.detached {
      Result { try OnePasswordService().loadCredentials(item: item, vault: vault, account: account) }
    }.value

    switch result {
    case .success(let loadedCredentials):
      credentials = loadedCredentials
      setAutofillMessage(nil)
    case .failure(let error):
      credentials = nil
      setAutofillMessage("1Password: \(error.localizedDescription) Log in manually.", failed: true)
    }

    startLogin()
  }

  private func startLogin() {
    promptDetector = LoginPromptDetector()
    phase = .running

    let request = EmbeddedTerminalRequest.command(
      loginCommand,
      title: "Teleport Login",
      summary: "Running tsh login"
    )

    if let terminalStore {
      terminalStore.run(request: request, connectedNodeID: nil)
    } else {
      let terminalStore = TerminalSessionStore(
        windowState: DesktopWindowState(request: request, selectedNodeID: nil, connectedNodeID: nil)
      )
      configure(terminalStore)
      self.terminalStore = terminalStore
    }

    focusToken += 1
  }

  private func handleOutput(_ text: String) {
    guard let credentials, let prompt = promptDetector.consume(text) else {
      return
    }

    switch prompt {
    case .password:
      answer(with: credentials.password, message: "Password filled from 1Password")
    case .oneTimePassword:
      guard let item = settings.onePasswordLoginItem else {
        return
      }

      // Read the code only when tsh asks for it so it is as fresh as possible.
      let vault = settings.normalizedOnePasswordVault
      let account = settings.normalizedOnePasswordAccount
      Task {
        let result = await Task.detached {
          Result { try OnePasswordService().loadOneTimePassword(item: item, vault: vault, account: account) }
        }.value

        switch result {
        case .success(let code):
          answer(with: code, message: "Password and OTP filled from 1Password")
        case .failure(let error):
          setAutofillMessage("1Password: \(error.localizedDescription) Enter the OTP manually.", failed: true)
        }
      }
    }
  }

  private func answer(with secret: String, message: String) {
    let terminalStore = terminalStore

    Task {
      // Give tsh a moment to switch the terminal to no-echo mode so the
      // secret is never shown.
      try? await Task.sleep(for: .milliseconds(250))

      guard phase == .running, let terminalStore, terminalStore === self.terminalStore else {
        return
      }

      terminalStore.terminalController.sendInput(secret + "\r")
      setAutofillMessage(message)
    }
  }

  private func setAutofillMessage(_ message: String?, failed: Bool = false) {
    autofillMessage = message
    autofillFailed = failed
  }

  private func processTerminated(exitCode: Int32?) {
    terminalStore?.processTerminated(exitCode: exitCode)

    guard exitCode == 0 else {
      phase = .failed(exitCode)
      SoundFeedbackService.play(.error, settings: settings)
      return
    }

    phase = .verifying
    Task {
      await store.refresh(using: settings)

      if store.session.isActive {
        close()
      } else {
        phase = .noSession
      }
    }
  }

  private func retry() {
    if settings.onePasswordLoginItem != nil && credentials == nil {
      Task {
        await unlockAndStart()
      }
    } else {
      startLogin()
    }
  }

  private func close() {
    dismiss()
  }
}
