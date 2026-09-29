import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: BoxStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = Scanner()
    @State private var showPicker = false
    @State private var folderName = CloudFolderSync.displayName
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Folder", value: folderName ?? "not chosen")
                    Button("Choose sync folder") { showPicker = true }
                    if folderName != nil {
                        Button("Forget folder", role: .destructive) { CloudFolderSync.forget(); folderName = nil }
                    }
                    Toggle("Export CSV after every scan", isOn: $store.autoExport)
                } header: {
                    Text("Sync folder")
                } footer: {
                    Text("Pick iCloud Drive > Pokemon GO. The Mac watches that folder and imports each CSV the moment it syncs.")
                }
                Section {
                    LabeledContent("Last scan", value: store.lastScan?.formatted(date: .abbreviated, time: .shortened) ?? "never")
                    Button("Rescan the last 7 days") {
                        Task { await scanner.scan(into: store, mode: .recent(days: 7)); message = scanner.lastReport }
                    }
                    .disabled(scanner.isScanning)
                    Button("Rescan the newest 300 screenshots") {
                        Task { await scanner.scan(into: store, mode: .everything); message = scanner.lastReport }
                    }
                    .disabled(scanner.isScanning)
                    if scanner.isScanning {
                        HStack { ProgressView(); Text(scanner.progress.isEmpty ? "Scanning" : scanner.progress).font(.footnote) }
                    }
                    Toggle("Write OCR debug files to the sync folder", isOn: $store.debugExport)
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                } header: {
                    Text("Scanning")
                } footer: {
                    Text("Debug files hold the text the OCR saw on each screenshot, with positions, so the parsers can be tuned on the Mac. Turn it off once scans look right.")
                }
                Section {
                    Toggle("Banner for each Pokémon read during a live scan", isOn: Binding(
                        get: { AppGroup.defaults?.object(forKey: "pl-live-banners") as? Bool ?? true },
                        set: { AppGroup.defaults?.set($0, forKey: "pl-live-banners") }))
                } header: {
                    Text("Live scan")
                }
                Section {
                    Button("Clear the box", role: .destructive) { store.clear() }
                } footer: {
                    Text("Pogo Lens reads your screenshots only. It never logs in to Pokémon GO and sends nothing to Niantic.")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showPicker) {
                FolderPicker { url in
                    do { try CloudFolderSync.remember(url); folderName = CloudFolderSync.displayName; message = nil }
                    catch { message = error.localizedDescription }
                }
            }
        }
    }
}
