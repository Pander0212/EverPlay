import SwiftUI

/// RPG Maker MV/MZ cheats, backed by App/Resources/RPGMakerCheats.js inside the running game.
struct CheatsView: View {
    @ObservedObject var session: GameSession
    @State private var status: CheatStatus?
    @State private var failure: String?

    var body: some View {
        Form {
            if let status, status.ready {
                Section("Gold") {
                    LabeledContent("Gold", value: Self.format(status.gold ?? 0))
                    HStack {
                        ForEach([1_000, 10_000, 100_000], id: \.self) { amount in
                            Button("+\(Self.format(Double(amount)))") { run("addGold", [amount]) }
                        }
                        Button("Max") { run("setGold", [status.maxGold ?? 99_999_999]) }
                    }
                    .buttonStyle(.bordered)
                }
                Section("Party") {
                    ForEach(status.party ?? []) { actor in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(actor.name)  ·  Lv \(Int(actor.level))").font(.headline)
                            Text("HP \(Int(actor.hp))/\(Int(actor.mhp))   MP \(Int(actor.mp))/\(Int(actor.mmp))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Button("Heal all") { run("heal") }
                        Button("Level +1") { run("levelUp", [1]) }
                        Button("Level +10") { run("levelUp", [10]) }
                    }
                    .buttonStyle(.bordered)
                }
                Section {
                    Picker("Game speed", selection: Binding(get: { Int(status.speed ?? 1) }, set: { run("setSpeed", [$0]) })) {
                        ForEach([1, 2, 3, 4], id: \.self) { Text("\($0)×").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Walk through walls", isOn: Binding(get: { status.through ?? false }, set: { run("setThrough", [$0]) }))
                    Toggle("No random encounters", isOn: Binding(get: { status.noEncounters ?? false },
                                                                 set: { run("setNoEncounters", [$0]) }))
                } header: {
                    Text("Gameplay")
                } footer: {
                    Text("Speed runs the game's logic several times per frame. Walk-through and encounters last until the game closes.")
                }
                Section("Inventory and flags") {
                    NavigationLink("Items") { CheatItemsView(target: RunningGame(session: session), kind: "item", title: "Items") }
                    NavigationLink("Weapons") { CheatItemsView(target: RunningGame(session: session), kind: "weapon", title: "Weapons") }
                    NavigationLink("Armor") { CheatItemsView(target: RunningGame(session: session), kind: "armor", title: "Armor") }
                    NavigationLink("Variables") { CheatVariablesView(target: RunningGame(session: session)) }
                    NavigationLink("Switches") { CheatSwitchesView(target: RunningGame(session: session)) }
                }
            } else {
                Section {
                    Text(status == nil ? "Connecting to the game…" : "Start a new game or load a save first; cheats need the game's party.")
                    Button("Check again") { Task { await refresh() } }
                }
            }
            if let failure {
                Section { Text(failure).foregroundStyle(.red).font(.footnote) }
            }
        }
        .navigationTitle("Cheats")
        .task { await refresh() }
    }

    private func refresh() async {
        do { status = try await session.cheat("status", as: CheatStatus.self); failure = nil }
        catch { failure = "The game did not answer: \(error.localizedDescription)" }
    }

    private func run(_ method: String, _ arguments: [Any] = []) {
        Task {
            do { status = try await session.cheat(method, arguments, as: CheatStatus.self); failure = nil }
            catch { failure = "That did not work in this game: \(error.localizedDescription)" }
        }
    }

    static func format(_ value: Double) -> String {
        value.rounded() == value ? Int(value).formatted() : value.formatted()
    }
}

struct CheatStatus: Decodable {
    let engine: String?
    let ready: Bool
    let gold: Double?
    let maxGold: Double?
    let party: [CheatActor]?
    let speed: Double?
    let through: Bool?
    let noEncounters: Bool?
}

struct CheatActor: Decodable, Identifiable {
    let id: Int
    let name: String
    let level: Double
    let hp: Double
    let mhp: Double
    let mp: Double
    let mmp: Double
}

struct CheatItem: Decodable, Identifiable {
    let id: Int
    let name: String
    let count: Double
    let max: Double
}

/// A variable's value as the game stores it (usually a number).
enum CheatValue: Decodable {
    case number(Double), text(String), flag(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) { self = .number(number) }
        else if let flag = try? container.decode(Bool.self) { self = .flag(flag) }
        else { self = .text(try container.decode(String.self)) }
    }

    var display: String {
        switch self {
        case .number(let value): return CheatsView.format(value)
        case .text(let value): return "“\(value)”"
        case .flag(let value): return value ? "true" : "false"
        }
    }
}

struct CheatVariable: Decodable, Identifiable {
    let id: Int
    let name: String
    let value: CheatValue
    let number: Bool
}

struct CheatSwitch: Decodable, Identifiable {
    let id: Int
    let name: String
    let value: Bool
}

/// What the item, variable and switch lists change: the running game or a save slot (SaveEditorView).
@MainActor
protocol CheatTarget {
    func items(_ kind: String, _ query: String) async throws -> [CheatItem]
    func gainItem(_ kind: String, _ id: Int, _ amount: Int) async throws
    func variables(_ query: String) async throws -> [CheatVariable]
    func setVariable(_ id: Int, _ value: Double) async throws
    func switches(_ query: String) async throws -> [CheatSwitch]
    func setSwitch(_ id: Int, _ on: Bool) async throws
}

/// The game as it runs now (RPGMakerCheats.js).
struct RunningGame: CheatTarget {
    let session: GameSession

    func items(_ kind: String, _ query: String) async throws -> [CheatItem] {
        try await session.cheat("items", [kind, query], as: [CheatItem].self)
    }
    func gainItem(_ kind: String, _ id: Int, _ amount: Int) async throws {
        _ = try await session.cheat("gainItem", [kind, id, amount], as: Bool.self)
    }
    func variables(_ query: String) async throws -> [CheatVariable] {
        try await session.cheat("variables", [query], as: [CheatVariable].self)
    }
    func setVariable(_ id: Int, _ value: Double) async throws {
        _ = try await session.cheat("setVariable", [id, value], as: Bool.self)
    }
    func switches(_ query: String) async throws -> [CheatSwitch] {
        try await session.cheat("switches", [query], as: [CheatSwitch].self)
    }
    func setSwitch(_ id: Int, _ on: Bool) async throws {
        _ = try await session.cheat("setSwitch", [id, on], as: Bool.self)
    }
}

struct CheatItemsView: View {
    let target: CheatTarget
    let kind: String
    let title: String
    @State private var query = ""
    @State private var items: [CheatItem] = []

    var body: some View {
        List(items) { item in
            HStack {
                VStack(alignment: .leading) {
                    Text(item.name)
                    Text("\(Int(item.count)) of \(Int(item.max))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("+1") { gain(item, 1) }
                Button("+10") { gain(item, 10) }
                Button("Max") { gain(item, Int(item.max - item.count)) }
            }
            .buttonStyle(.bordered)
        }
        .overlay { if items.isEmpty { ContentUnavailableView.search } }
        .searchable(text: $query, prompt: "Name, #id or =count")
        .navigationTitle(title)
        .task(id: query) { await load() }
    }

    private func load() async {
        items = (try? await target.items(kind, query)) ?? []
    }

    private func gain(_ item: CheatItem, _ amount: Int) {
        Task {
            try? await target.gainItem(kind, item.id, amount)
            await load()
        }
    }
}

struct CheatVariablesView: View {
    let target: CheatTarget
    @State private var query = ""
    @State private var variables: [CheatVariable] = []
    @State private var editing: CheatVariable?
    @State private var text = ""

    var body: some View {
        List(variables) { variable in
            HStack {
                VStack(alignment: .leading) {
                    Text(variable.name.isEmpty ? "Variable \(variable.id)" : variable.name)
                    Text("#\(variable.id)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(variable.value.display).monospacedDigit()
                if variable.number {
                    Button("Edit") {
                        if case .number(let value) = variable.value { text = CheatsView.format(value) }
                        editing = variable
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .overlay { if variables.isEmpty { ContentUnavailableView.search } }
        .searchable(text: $query, prompt: "Name, #id or =value")
        .navigationTitle("Variables")
        .task(id: query) { await load() }
        .alert(editing.map { $0.name.isEmpty ? "Variable \($0.id)" : $0.name } ?? "",
               isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Value", text: $text).keyboardType(.numbersAndPunctuation)
            Button("Set") {
                if let variable = editing, let value = Double(text.replacingOccurrences(of: ",", with: ".")) {
                    Task {
                        try? await target.setVariable(variable.id, value)
                        await load()
                    }
                }
                editing = nil
            }
            Button("Cancel", role: .cancel) { editing = nil }
        }
    }

    private func load() async {
        variables = (try? await target.variables(query)) ?? []
    }
}

struct CheatSwitchesView: View {
    let target: CheatTarget
    @State private var query = ""
    @State private var switches: [CheatSwitch] = []

    var body: some View {
        List(switches) { entry in
            Toggle(isOn: Binding(get: { entry.value }, set: { on in
                Task {
                    try? await target.setSwitch(entry.id, on)
                    await load()
                }
            })) {
                VStack(alignment: .leading) {
                    Text(entry.name.isEmpty ? "Switch \(entry.id)" : entry.name)
                    Text("#\(entry.id)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .overlay { if switches.isEmpty { ContentUnavailableView.search } }
        .searchable(text: $query, prompt: "Name or #id")
        .navigationTitle("Switches")
        .task(id: query) { await load() }
    }

    private func load() async {
        switches = (try? await target.switches(query)) ?? []
    }
}
