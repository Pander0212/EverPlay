import SwiftUI
import UniformTypeIdentifiers

/// A game's remembered translations (game page › Edit translations): search, correct, delete,
/// export to share and import someone else's. Changes apply the next time the game starts.
struct TranslationMemoryView: View {
    let game: String
    let language: String
    @State private var lines: [String: String] = [:]
    @State private var query = ""
    @State private var editing: String?
    @State private var text = ""
    @State private var importing = false
    @State private var confirmClear = false
    @State private var notice: String?

    private var file: URL { TranslationEngine.memoryFile(game: game, language: language) }

    private var shown: [(source: String, translation: String)] {
        lines.filter { query.isEmpty || $0.key.localizedCaseInsensitiveContains(query) || $0.value.localizedCaseInsensitiveContains(query) }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        List {
            if let notice {
                Text(notice).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(shown, id: \.source) { line in
                Button {
                    text = line.translation
                    editing = line.source
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(line.source).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                        Text(line.translation).foregroundStyle(.primary).lineLimit(4)
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { lines[line.source] = nil; save() }
                }
            }
        }
        .overlay {
            if lines.isEmpty {
                ContentUnavailableView("No translations yet", systemImage: "character.bubble",
                                       description: Text("Play with translation on; every translated line shows up here."))
            } else if shown.isEmpty {
                ContentUnavailableView.search
            }
        }
        .searchable(text: $query, prompt: "Original or translation")
        .navigationTitle("Translations (\(lines.count))")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !lines.isEmpty {
                        ShareLink(item: file, preview: SharePreview("Translations \(language)")) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button("Import…", systemImage: "square.and.arrow.down") { importing = true }
                    if !lines.isEmpty {
                        Button("Delete all", systemImage: "trash", role: .destructive) { confirmClear = true }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("translationMemoryMenu")
            }
        }
        .alert("Translation", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Translation", text: $text, axis: .vertical)
            Button("Save") {
                if let source = editing, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines[source] = text
                    save()
                }
                editing = nil
            }
            Button("Cancel", role: .cancel) { editing = nil }
        } message: {
            Text(editing ?? "")
        }
        .confirmationDialog("Delete all \(lines.count) translations?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { lines = [:]; save() }
        } message: {
            Text("They are translated again the next time the lines appear.")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let imported = try? JSONDecoder().decode([String: String].self, from: data) else {
                notice = "That file is not an EverPlay translation export."
                return
            }
            let added = imported.keys.filter { lines[$0] == nil }.count
            lines.merge(imported) { _, new in new }
            save()
            notice = "Imported \(imported.count) lines (\(added) new)."
        }
        .task { load() }
    }

    private func load() {
        lines = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))) ?? [:]
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if lines.isEmpty {
                try? FileManager.default.removeItem(at: file)
            } else {
                try JSONEncoder().encode(lines).write(to: file, options: .atomic)
            }
        } catch {
            notice = "Could not save: \(error.localizedDescription)"
        }
    }
}
