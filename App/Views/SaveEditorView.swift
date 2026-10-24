import SwiftUI

/// RPG Maker MV/MZ save editor: changes a save slot without loading it, backed by
/// App/Resources/RPGMakerSaves.js inside the running game.
struct SaveEditorView: View {
    @ObservedObject var session: GameSession
    @State private var slots: [SaveSlot]?
    @State private var failure: String?

    var body: some View {
        Form {
            if let slots, !slots.isEmpty {
                Section {
                    ForEach(slots) { slot in
                        NavigationLink { SaveSlotEditorView(session: session, slot: slot) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(slot.label).font(.headline)
                                Text(slot.details).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("saveSlot-\(slot.id)")
                    }
                } footer: {
                    Text("Changes are written to the save itself. Load that save in the game afterwards to play with them.")
                }
            } else {
                Section {
                    Text(slots == nil ? "Reading the game's saves…" : "No saves yet. Save in the game first, then come back.")
                    Button("Check again") { Task { await load() } }
                }
            }
            if let failure {
                Section { Text(failure).foregroundStyle(.red).font(.footnote) }
            }
        }
        .navigationTitle("Save editor")
        .task { await load() }
    }

    private func load() async {
        do { slots = try await session.saveEdit("slots", as: [SaveSlot].self); failure = nil }
        catch { failure = "The game did not answer: \(SaveSlotTarget.message(error))" }
    }
}

struct SaveSlot: Decodable, Identifiable {
    let id: Int
    let title: String
    let playtime: String
    let timestamp: Double
    let autosave: Bool

    var label: String { autosave ? "Autosave" : "Slot \(id)" }

    var details: String {
        var parts: [String] = []
        if !title.isEmpty { parts.append(title) }
        if !playtime.isEmpty { parts.append(playtime) }
        if timestamp > 0 {
            parts.append(Date(timeIntervalSince1970: timestamp / 1000).formatted(date: .abbreviated, time: .shortened))
        }
        return parts.joined(separator: " · ")
    }
}

struct SaveSummary: Decodable {
    let id: Int
    let gold: Double
    let maxGold: Double
    let actors: [SaveActor]
}

struct SaveActor: Decodable, Identifiable {
    let index: Int
    let id: Int
    let name: String
    let level: Double
    let maxLevel: Double
}

/// One save slot as the target of the shared item, variable and switch lists.
struct SaveSlotTarget: CheatTarget {
    let session: GameSession
    let slot: Int

    func items(_ kind: String, _ query: String) async throws -> [CheatItem] {
        try await session.saveEdit("items", [slot, kind, query], as: [CheatItem].self)
    }
    func gainItem(_ kind: String, _ id: Int, _ amount: Int) async throws {
        _ = try await session.saveEdit("gainItem", [slot, kind, id, amount], as: Bool.self)
    }
    func variables(_ query: String) async throws -> [CheatVariable] {
        try await session.saveEdit("variables", [slot, query], as: [CheatVariable].self)
    }
    func setVariable(_ id: Int, _ value: Double) async throws {
        _ = try await session.saveEdit("setVariable", [slot, id, value], as: Bool.self)
    }
    func switches(_ query: String) async throws -> [CheatSwitch] {
        try await session.saveEdit("switches", [slot, query], as: [CheatSwitch].self)
    }
    func setSwitch(_ id: Int, _ on: Bool) async throws {
        _ = try await session.saveEdit("setSwitch", [slot, id, on], as: Bool.self)
    }

    /// The script's own message ("this save slot is empty") instead of WebKit's generic one.
    static func message(_ error: Error) -> String {
        (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
    }
}

private struct SaveSlotEditorView: View {
    @ObservedObject var session: GameSession
    let slot: SaveSlot
    @State private var summary: SaveSummary?
    @State private var failure: String?
    @State private var gold = ""
    @State private var editingActor: SaveActor?
    @State private var level = ""

    var body: some View {
        Form {
            if let summary {
                Section("Gold") {
                    HStack {
                        TextField("Gold", text: $gold).keyboardType(.numberPad).accessibilityIdentifier("saveGold")
                        Button("Set") { if let value = Double(gold) { run("setGold", [slot.id, value]) } }
                        Button("Max") { run("setGold", [slot.id, summary.maxGold]) }
                    }
                    .buttonStyle(.bordered)
                }
                Section("Party") {
                    ForEach(summary.actors) { actor in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(actor.name.isEmpty ? "Actor \(actor.id)" : actor.name)
                                Text("Level \(Int(actor.level)) of \(Int(actor.maxLevel))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Level") { level = String(Int(actor.level)); editingActor = actor }
                            Button("Max") { run("setLevel", [slot.id, actor.index, actor.maxLevel]) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Section("Inventory and flags") {
                    let target = SaveSlotTarget(session: session, slot: slot.id)
                    NavigationLink("Items") { CheatItemsView(target: target, kind: "item", title: "Items") }
                    NavigationLink("Weapons") { CheatItemsView(target: target, kind: "weapon", title: "Weapons") }
                    NavigationLink("Armor") { CheatItemsView(target: target, kind: "armor", title: "Armor") }
                    NavigationLink("Variables") { CheatVariablesView(target: target) }
                    NavigationLink("Switches") { CheatSwitchesView(target: target) }
                }
            } else if failure == nil {
                Section { Text("Reading \(slot.label)…") }
            }
            if let failure {
                Section { Text(failure).foregroundStyle(.red).font(.footnote) }
            }
        }
        .navigationTitle(slot.label)
        .task { await load() }
        .alert(editingActor.map { $0.name.isEmpty ? "Actor \($0.id)" : $0.name } ?? "",
               isPresented: Binding(get: { editingActor != nil }, set: { if !$0 { editingActor = nil } })) {
            TextField("Level", text: $level).keyboardType(.numberPad)
            Button("Set") {
                if let actor = editingActor, let value = Double(level) { run("setLevel", [slot.id, actor.index, value]) }
                editingActor = nil
            }
            Button("Cancel", role: .cancel) { editingActor = nil }
        }
    }

    private func show(_ result: SaveSummary) {
        summary = result
        gold = String(Int(result.gold))
        failure = nil
    }

    private func load() async {
        do { show(try await session.saveEdit("summary", [slot.id], as: SaveSummary.self)) }
        catch { failure = "This save could not be read: \(SaveSlotTarget.message(error))" }
    }

    private func run(_ method: String, _ arguments: [Any]) {
        Task {
            do { show(try await session.saveEdit(method, arguments, as: SaveSummary.self)) }
            catch { failure = "That did not work for this save: \(SaveSlotTarget.message(error))" }
        }
    }
}
