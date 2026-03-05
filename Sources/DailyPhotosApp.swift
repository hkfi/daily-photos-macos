import SwiftUI

@main
struct DailyPhotosApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        // ── Menu bar icon + popover ──
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .onAppear {
                    // First launch: open settings so the user picks a vault folder
                    if appState.vaultPath.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                        }
                    }
                }
        } label: {
            Label("Daily Photos", systemImage: appState.isImporting ? "arrow.down.circle" : "photo.on.rectangle")
        }
        .menuBarExtraStyle(.window)

        // ── Settings window ──
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
