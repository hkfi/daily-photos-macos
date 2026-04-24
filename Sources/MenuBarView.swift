import SwiftUI

/// The popover that appears when clicking the menu bar icon.
/// Shows import status, recent imports, and quick actions.

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings

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

            // ── Update banner ──
            if appState.updater.updateAvailable, let version = appState.updater.latestVersion {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.orange)
                        Text("Update available: v\(version)")
                            .font(.callout)
                            .fontWeight(.medium)
                        Spacer()
                    }

                    if appState.updater.isUpdating {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Installing update…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Button {
                            Task { await appState.updater.downloadAndInstall() }
                        } label: {
                            Text("Install & Relaunch")
                                .font(.callout)
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.small)
                    }

                    if let error = appState.updater.updateError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
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
                    .menuActionRow()
                }
                .buttonStyle(.plain)
                .disabled(appState.isImporting)
                .keyboardShortcut("i", modifiers: .command)

                Button {
                    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                    Task { await appState.runImport(dateRange: .single(yesterday)) }
                } label: {
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                        Text("Import Yesterday")
                        Spacer()
                    }
                    .menuActionRow()
                }
                .buttonStyle(.plain)
                .disabled(appState.isImporting)

                // Toggle auto-import
                Button {
                    appState.autoImportEnabled.toggle()
                } label: {
                    HStack {
                        Image(systemName: appState.autoImportEnabled ? "pause.circle" : "play.circle")
                        Text(appState.autoImportEnabled ? "Pause Auto-Import" : "Resume Auto-Import")
                        Spacer()
                    }
                    .menuActionRow()
                }
                .buttonStyle(.plain)

                // Check for updates
                if !appState.updater.updateAvailable {
                    Button {
                        Task { await appState.updater.checkForUpdates() }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(appState.updater.isChecking ? "Checking…" : "Check for Updates")
                            Spacer()
                        }
                        .menuActionRow()
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.updater.isChecking)
                }

                Divider()

                // Settings
                Button {
                    openSettings()
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
                    .menuActionRow()
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
                    .menuActionRow()
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 300)
        .padding(.bottom, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var statusColor: Color {
        if appState.isImporting { return .orange }
        if appState.autoImportEnabled { return .green }
        return .gray
    }
}

private struct MenuActionRowModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered && isEnabled ? Color.accentColor.opacity(0.18) : Color.clear)
            }
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.08), value: isHovered)
    }
}

private extension View {
    func menuActionRow() -> some View {
        modifier(MenuActionRowModifier())
    }
}
