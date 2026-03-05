import SwiftUI

@main
struct DailyPhotosApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        // ── Menu bar icon + popover ──
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .onAppear {
                    // First launch: open settings so the user picks a vault folder
                    if appState.vaultPath.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            openSettings()
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    }
                }
        } label: {
            Label("Daily Photos", systemImage: appState.updater.updateAvailable
                  ? "arrow.down.circle.fill"
                  : appState.isImporting ? "arrow.down.circle" : "photo.on.rectangle")
        }
        .menuBarExtraStyle(.window)

        // ── Settings window ──
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
