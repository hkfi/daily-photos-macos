import SwiftUI

/// Single-page settings window. No tabs — everything fits on one screen.

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var backfillStartDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var backfillEndDate = Date()

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: appState.updater.updateAvailable ? "arrow.down.circle.fill" : "photo.on.rectangle.angled")
                        .font(.system(size: 28))
                        .foregroundColor(appState.updater.updateAvailable ? .orange : .accentColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Daily Photos \(appState.updater.currentVersion)")
                            .font(.headline)

                        Text(updateSummary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if appState.updater.isUpdating {
                        ProgressView()
                            .controlSize(.small)
                    } else if appState.updater.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    } else if appState.updater.updateAvailable {
                        Button("Install Update") {
                            Task { await appState.updater.downloadAndInstall() }
                        }
                    } else {
                        Button("Check Now") {
                            Task { await appState.updater.checkForUpdates() }
                        }
                    }
                }

                if let error = appState.updater.updateError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            } header: {
                Text("App")
            }

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
                TextField("Date format", text: $appState.dateFormat)
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

                Toggle("Favorites only", isOn: $appState.favoritesOnly)
                    .tint(.accentColor)

                Toggle("Exclude screenshots", isOn: $appState.excludeScreenshots)
                    .tint(.accentColor)
            } header: {
                Text("Import behavior")
            }

            // ── Daily note ──
            Section {
                Toggle("Append to daily note", isOn: $appState.appendToDailyNote)
                    .tint(.accentColor)

                if appState.appendToDailyNote {
                    TextField("Note path", text: $appState.dailyNotePathTemplate)
                        .font(.callout)

                    TextField("Section heading", text: $appState.dailyNoteHeading)
                        .font(.callout)
                }
            } header: {
                Text("Daily note")
            }

            // ── Backfill ──
            Section {
                DatePicker("From", selection: $backfillStartDate, displayedComponents: .date)
                DatePicker("To", selection: $backfillEndDate, displayedComponents: .date)

                Button {
                    Task {
                        await appState.runImport(
                            dateRange: ImportDateRange(
                                startDate: backfillStartDate,
                                endDate: backfillEndDate
                            )
                        )
                    }
                } label: {
                    Text(appState.isImporting ? "Importing…" : "Import Date Range")
                }
                .disabled(appState.isImporting || appState.vaultPath.isEmpty)
            } header: {
                Text("Backfill")
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
                    Text("\(appState.trackedPhotoCount)")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Status")
            }

        }
        .formStyle(.grouped)
        .frame(width: 420, height: 720)
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

    private var updateSummary: String {
        if let version = appState.updater.latestVersion, appState.updater.updateAvailable {
            return "Version \(version) is ready to install."
        }

        if appState.updater.isUpdating {
            return "Installing the latest release…"
        }

        if appState.updater.isChecking {
            return "Checking GitHub Releases…"
        }

        return "Version and update controls live here."
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
