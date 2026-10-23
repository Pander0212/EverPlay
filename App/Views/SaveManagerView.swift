import SwiftUI

/// Save files of a game in On My iPhone › EverPlay › Saves: list, back up, restore, share and delete.
/// Ren'Py saves are Python pickles; EverPlay never opens them (that would run code from the file).
/// Their values are edited inside the game with the EverPlay menu's variable editor.
struct SaveManagerView: View {
    let title: String
    let folder: URL
    @State private var saves: [URL] = []
    @State private var backups: [URL] = []
    @State private var notice: String?
    @State private var deleteCandidate: URL?
    @State private var restoreCandidate: URL?

    private var backupRoot: URL { folder.appendingPathComponent("EverPlay backups", isDirectory: true) }

    var body: some View {
        List {
            Section {
                Label("Edit money, stats or flags: open the game, load the save, tap the ☰ button › Variables, change the values, then save again.",
                      systemImage: "slider.horizontal.3")
                    .font(.footnote)
            } header: {
                Text("Editing values")
            }
            Section {
                if saves.isEmpty {
                    Text("No saves yet.").foregroundStyle(.secondary)
                }
                ForEach(saves, id: \.self) { file in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.lastPathComponent).font(.subheadline.weight(.semibold))
                            Text(details(of: file)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        ShareLink(item: file) { Image(systemName: "square.and.arrow.up") }
                            .buttonStyle(.borderless)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { deleteCandidate = file }
                    }
                }
            } header: {
                Text("Save files")
            } footer: {
                Text("Files app: On My iPhone › EverPlay › Saves › \(folder.lastPathComponent). Share a save to keep it elsewhere or to move it to another device.")
            }
            Section {
                Button("Back up all saves now", systemImage: "externaldrive.badge.plus") { backUp() }
                    .disabled(saves.isEmpty)
                ForEach(backups, id: \.self) { backup in
                    Button {
                        restoreCandidate = backup
                    } label: {
                        Label(backup.lastPathComponent, systemImage: "clock.arrow.circlepath")
                    }
                }
            } header: {
                Text("Backups")
            } footer: {
                Text("Restoring replaces the current save files with the backup's; the current ones are backed up first.")
            }
        }
        .navigationTitle("Saves")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .alert("EverPlay", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK") { notice = nil }
        } message: { Text(notice ?? "") }
        .confirmationDialog("Delete \(deleteCandidate?.lastPathComponent ?? "")?",
                            isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })) {
            Button("Delete save", role: .destructive) {
                if let file = deleteCandidate { try? FileManager.default.removeItem(at: file) }
                deleteCandidate = nil
                reload()
            }
        }
        .confirmationDialog("Restore \(restoreCandidate?.lastPathComponent ?? "")?",
                            isPresented: Binding(get: { restoreCandidate != nil }, set: { if !$0 { restoreCandidate = nil } })) {
            Button("Restore backup") { if let backup = restoreCandidate { restore(backup) }; restoreCandidate = nil }
        }
    }

    private func details(of file: URL) -> String {
        let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let date = values?.contentModificationDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? ""
        let size = ByteCountFormatter.string(fromByteCount: Int64(values?.fileSize ?? 0), countStyle: .file)
        return "\(date) · \(size)"
    }

    private func reload() {
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
                                                      options: [.skipsHiddenFiles])) ?? []
        saves = files.filter { file in
            (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        backups = ((try? manager.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    @discardableResult
    private func backUp() -> Bool {
        let stamp = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let target = backupRoot.appendingPathComponent(stamp, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            for file in saves { try FileManager.default.copyItem(at: file, to: target.appendingPathComponent(file.lastPathComponent)) }
            notice = "Backed up \(saves.count) files."
            EverPlayLog.write("Backed up \(saves.count) save files of \(title)")
            reload()
            return true
        } catch {
            notice = "The backup failed: \(error.localizedDescription)"
            return false
        }
    }

    private func restore(_ backup: URL) {
        if !saves.isEmpty && !backUp() { return }
        do {
            for file in saves { try FileManager.default.removeItem(at: file) }
            for file in try FileManager.default.contentsOfDirectory(at: backup, includingPropertiesForKeys: nil) {
                try FileManager.default.copyItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
            }
            notice = "Restored \(backup.lastPathComponent)."
            EverPlayLog.write("Restored save backup \(backup.lastPathComponent) of \(title)")
        } catch {
            notice = "Restoring failed: \(error.localizedDescription)"
        }
        reload()
    }
}
