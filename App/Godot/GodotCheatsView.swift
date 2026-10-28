import SwiftUI

/// Cheats for a running Godot game: every variable of its global scripts (autoloads such as
/// GameState) and of the current scene, searchable by name or =value, editable in place, and the
/// game's speed. Works with any GDScript game; what the variables mean depends on the game.
struct GodotCheatsView: View {
    let engine: GodotEngine
    @State private var variables: [GodotVariable] = []
    @State private var search = ""
    @State private var speed = 1.0
    @State private var editing: GodotVariable?
    @State private var failure: String?

    var body: some View {
        List {
            if engine.setSpeed != nil {
                Section {
                    Picker("Game speed", selection: Binding(get: { speed }, set: { setSpeed($0) })) {
                        ForEach([0.5, 1, 2, 3, 4], id: \.self) { Text($0 == 0.5 ? "½×" : "\(Int($0))×").tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Speed lasts until the game closes.")
                }
            }
            Section {
                if engine.variables == nil {
                    Text("This Godot engine has no cheats yet; update EverPlay.")
                } else if variables.isEmpty {
                    Text("No variables found. Start or load a game first, then tap Refresh.")
                }
                ForEach(shown) { variable in
                    row(variable)
                }
            } header: {
                Text(variables.isEmpty ? "Variables" : "Variables (\(shown.count) of \(variables.count))")
            } footer: {
                Text("Search by name, or by value with =100. Changes apply at once; save in the game to keep them.")
            }
            if let failure {
                Section { Text(failure).foregroundStyle(.red).font(.footnote) }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name or =value")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .navigationTitle("Cheats")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Refresh", systemImage: "arrow.clockwise") { refresh() }
            }
        }
        .sheet(item: $editing) { variable in
            NavigationStack { GodotVariableEditor(variable: variable) { text in apply(variable, text) } }
                .presentationDetents([.medium])
        }
        .onAppear { refresh() }
    }

    private var shown: [GodotVariable] {
        let query = search.trimmingCharacters(in: .whitespaces)
        if query.hasPrefix("=") {
            let wanted = String(query.dropFirst()).trimmingCharacters(in: .whitespaces)
            return variables.filter { $0.value.text == wanted }
        }
        guard !query.isEmpty else { return variables }
        return variables.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    @ViewBuilder private func row(_ variable: GodotVariable) -> some View {
        switch variable.value {
        case .flag(let flag):
            Toggle(isOn: Binding(get: { flag }, set: { apply(variable, $0 ? "true" : "false") })) {
                label(variable)
            }
        case .number(let number):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    label(variable)
                    Spacer()
                    Text(variable.value.text).monospacedDigit().foregroundStyle(.secondary)
                }
                HStack {
                    ForEach([-100.0, -10, -1, 1, 10, 100], id: \.self) { step in
                        Button(step > 0 ? "+\(Int(step))" : "\(Int(step))") {
                            apply(variable, GodotVariable.Value.number(number + step).text)
                        }
                    }
                    Spacer()
                    Button("Edit") { editing = variable }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        case .text:
            Button { editing = variable } label: {
                HStack {
                    label(variable)
                    Spacer()
                    Text(variable.value.text).lineLimit(1).foregroundStyle(.secondary)
                }
            }
            .tint(.primary)
        }
    }

    private func label(_ variable: GodotVariable) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(variable.path).font(.body.monospaced())
            Text(variable.node.split(separator: "/").last.map(String.init) ?? variable.node)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func refresh() {
        variables = engine.gameVariables()
    }

    private func apply(_ variable: GodotVariable, _ text: String) {
        failure = engine.set(variable, to: text) ? nil : "\(variable.name) could not be changed (the game may have left that scene)."
        refresh()
    }

    private func setSpeed(_ value: Double) {
        speed = value
        engine.setSpeed?(value)
    }
}

/// Types a new value for one variable.
private struct GodotVariableEditor: View {
    let variable: GodotVariable
    let save: (String) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField("Value", text: $text)
                    .keyboardType(isNumber ? .numbersAndPunctuation : .default)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text(variable.name)
            } footer: {
                Text("Type: \(variable.type)")
            }
        }
        .navigationTitle("Edit value")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save(text)
                    dismiss()
                }
            }
        }
        .onAppear { text = variable.value.text }
    }

    private var isNumber: Bool {
        if case .number = variable.value { return true }
        return false
    }
}
