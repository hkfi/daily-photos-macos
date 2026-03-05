import SwiftUI

/// Single-page settings window. No tabs — everything fits on one screen.

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            // ── Vault location ──
            Section {
                HStack {
                    if appState.vaultPath.isEmpty {
                        Text("No folder selected")
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.accentColor)
                        Text(abbreviatePath(appState.vaultPath))
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    Spacer()
                    Button("Choose…") { chooseVaultFolder() }
                }

                if !appState.hasVaultAccess && !appState.vaultPath.isEmpty {
                    Label("Access lost — please re-select.", systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                        .font(.caption)
                }

                TextField("Photo subfolder", text: $appState.photoSubfolder)
                Text("Use {{date}} for today's date. E.g. Photos/{{date}}")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Where to save photos")
            }

            // ── Import behavior ──
            Section {
                Toggle("Auto-import", isOn: $appState.autoImportEnabled)
                    .tint(.accentColor)

                if appState.autoImportEnabled {
                    Picker("Check every", selection: $appState.intervalMinutes) {
                        Text("5 min").tag(5)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                    }
                }

                Toggle("Convert HEIC → JPEG", isOn: $appState.convertToJpeg)
                    .tint(.accentColor)
            } header: {
                Text("Import behavior")
            }

            // ── Daily note ──
            Section {
                Toggle("Append to daily note", isOn: $appState.appendToDailyNote)
                    .tint(.accentColor)

                if appState.appendToDailyNote {
                    TextField("Notes subfolder", text: $appState.dailyNotesSubfolder)
                        .font(.callout)
                }
            } header: {
                Text("Daily note")
            }

            // ── Status ──
            Section {
                HStack {
                    Text("Photos access")
                    Spacer()
                    PhotosAccessBadge()
                }
                HStack {
                    Text("Photos tracked")
                    Spacer()
                    Text("\(appState.tracker.totalTracked)")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Status")
            }

            // ── About ──
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appState.updater.currentVersion)
                        .foregroundColor(.secondary)
                }

                HStack {
                    if appState.updater.updateAvailable, let version = appState.updater.latestVersion {
                        Label("v\(version) available", systemImage: "arrow.down.circle.fill")
                            .foregroundColor(.orange)
                        Spacer()
                        if appState.updater.isUpdating {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Button("Install & Relaunch") {
                                Task { await appState.updater.downloadAndInstall() }
                            }
                        }
                    } else {
                        Text("Updates")
                        Spacer()
                        if appState.updater.isChecking {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Button("Check for Updates") {
                                Task { await appState.updater.checkForUpdates() }
                            }
                        }
                    }
                }

                if let error = appState.updater.updateError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 540)
    }

    private func chooseVaultFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select your Obsidian vault"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            appState.saveVaultBookmark(for: url)
        }
    }

    private func abbreviatePath(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

// MARK: - First-run onboarding

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundColor(.accentColor)

            Text("Welcome to Daily Photos")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Pick your Obsidian vault folder and\nyou're good to go.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button("Choose Vault Folder…") {
                let panel = NSOpenPanel()
                panel.title = "Select your Obsidian vault"
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false

                if panel.runModal() == .OK, let url = panel.url {
                    appState.saveVaultBookmark(for: url)
                    appState.autoImportEnabled = true
                    dismiss()
                }
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)

            Button("Skip for now") {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .font(.caption)
        }
        .padding(40)
        .frame(width: 360)
    }
}

// MARK: - Helpers

struct PhotosAccessBadge: View {
    @State private var status: String = "Checking…"
    @State private var color: Color = .gray

    var body: some View {
        Text(status)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .cornerRadius(4)
            .task {
                let importer = PhotoImporter()
                let granted = await importer.requestAccess()
                status = granted ? "Authorized" : "Not Authorized"
                color = granted ? .green : .red
            }
    }
}
