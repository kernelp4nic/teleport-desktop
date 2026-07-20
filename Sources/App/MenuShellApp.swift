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
  @State private var libraryStore = NodeLibraryStore()

  var body: some Scene {
    WindowGroup("Teleport Desktop") {
      DesktopRootView(
        store: nodeStore,
        settings: settingsStore,
        library: libraryStore
      )
        .frame(minWidth: 1080, minHeight: 720)
    }
    .defaultSize(width: 1280, height: 820)

    MenuBarExtra {
      MenuBarRootView(
        store: nodeStore,
        settings: settingsStore,
        library: libraryStore
      )
        .frame(width: 420, height: 640)
    } label: {
      MenuBarIconView()
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView(settings: settingsStore, store: nodeStore)
        .frame(width: 420)
        .padding(20)
    }
  }
}
