import SwiftUI

/// The popover that appears when clicking the menu bar icon.
/// Shows import status, recent imports, and quick actions.

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                Text("Daily Photos")
                    .font(.headline)
                Spacer()
                if appState.isImporting {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // ── Status ──
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(appState.statusMessage)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                if let lastTime = appState.lastImportTime {
                    Text("Last import: \(lastTime, style: .relative) ago — \(appState.lastImportCount) photo(s)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if appState.autoImportEnabled {
                    Text("Auto-import every \(appState.intervalMinutes) min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // ── Recent imports ──
            if !appState.recentImports.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RECENT")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 2)

                    ForEach(appState.recentImports.prefix(5)) { item in
                        HStack {
                            Image(systemName: "photo")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(item.filename)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(item.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()
            }

            // ── Actions ──
            VStack(spacing: 2) {
                // Import now button
                Button {
                    Task { await appState.runImport() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                        Text("Import Now")
                        Spacer()
                        Text("⌘I")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
                .disabled(appState.isImporting)
                .keyboardShortcut("i", modifiers: .command)

                // Toggle auto-import
                Button {
                    appState.autoImportEnabled.toggle()
                } label: {
                    HStack {
                        Image(systemName: appState.autoImportEnabled ? "pause.circle" : "play.circle")
                        Text(appState.autoImportEnabled ? "Pause Auto-Import" : "Resume Auto-Import")
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)

                Divider()

                // Settings
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    HStack {
                        Image(systemName: "gear")
                        Text("Settings…")
                        Spacer()
                        Text("⌘,")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: .command)

                // Quit
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    HStack {
                        Image(systemName: "power")
                        Text("Quit")
                        Spacer()
                        Text("⌘Q")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.vertical, 4)
        }
        .frame(width: 300)
        .padding(.bottom, 8)
    }

    private var statusColor: Color {
        if appState.isImporting { return .orange }
        if appState.autoImportEnabled { return .green }
        return .gray
    }
}
