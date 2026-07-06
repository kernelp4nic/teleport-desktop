import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSWindow.allowsAutomaticWindowTabbing = false
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
}

@main
struct MenuShellApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var settingsStore = SettingsStore()
  @State private var nodeStore = TeleportNodeStore()

  var body: some Scene {
    WindowGroup("Teleport Desktop") {
      DesktopRootView(
        store: nodeStore,
        settings: settingsStore
      )
        .frame(minWidth: 1080, minHeight: 720)
    }
    .defaultSize(width: 1280, height: 820)

    Settings {
      SettingsView(settings: settingsStore, store: nodeStore)
        .frame(width: 420)
        .padding(20)
    }
  }
}
