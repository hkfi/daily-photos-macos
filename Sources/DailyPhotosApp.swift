import SwiftUI

@main
struct DailyPhotosApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.openSettings) private var openSettings
    @State private var hasOpenedInitialSettings = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .onAppear {
                    openSettingsIfNeeded()
                }
        } label: {
            Label("Daily Photos", systemImage: appState.updater.updateAvailable
                  ? "arrow.down.circle.fill"
                  : appState.isImporting ? "arrow.down.circle" : "photo.on.rectangle")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }

    private func openSettingsIfNeeded() {
        guard !hasOpenedInitialSettings, appState.vaultPath.isEmpty else { return }

        hasOpenedInitialSettings = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
