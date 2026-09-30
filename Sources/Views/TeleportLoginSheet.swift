import SwiftUI

/// Runs `tsh login` in a small embedded terminal and closes itself as soon as
/// the store detects an active Teleport session.
struct TeleportLoginSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Bindable var store: TeleportNodeStore
  @Bindable var settings: SettingsStore
  // Created in onAppear: SwiftUI re-runs init on every parent update, and
  // building the store eagerly would spawn a new `tsh login` each time.
  @State private var terminalStore: TerminalSessionStore?
  @State private var phase: Phase = .running
  @State private var focusToken = 0

  private enum Phase: Equatable {
    case running
    case verifying
    case failed(Int32?)
    case noSession
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
          Text(store.loginCommand(using: settings))
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
          Color.clear
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(.quaternary, lineWidth: 1)
      )

      HStack(spacing: 8) {
        statusView

        Spacer()

        if phase != .running && phase != .verifying {
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
      guard terminalStore == nil else {
        return
      }

      let terminalStore = TerminalSessionStore(
        windowState: DesktopWindowState.command(
          store.loginCommand(using: settings),
          title: "Teleport Login",
          summary: "Running tsh login"
        )
      )
      terminalStore.terminalController.onProcessTerminated = { exitCode in
        processTerminated(exitCode: exitCode)
      }
      self.terminalStore = terminalStore
      focusToken += 1
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
    case .running:
      Label("Waiting for login…", systemImage: "hourglass")
        .font(.caption)
        .foregroundStyle(.secondary)
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
    phase = .running
    terminalStore?.run(
      request: .command(
        store.loginCommand(using: settings),
        title: "Teleport Login",
        summary: "Running tsh login"
      ),
      connectedNodeID: nil
    )
    focusToken += 1
  }

  private func close() {
    dismiss()
  }
}
