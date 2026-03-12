import SwiftUI

struct NewPrototypeSheet: View {
    @EnvironmentObject var prototypeViewModel: PrototypeViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @FocusState private var nameFieldFocused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var isValid: Bool { !trimmed.isEmpty }
    private var previewSlug: String { SlugGenerator.generate(from: name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New Prototype")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g. Color Study", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFieldFocused)
                    .onSubmit { createIfValid() }
                if !name.isEmpty {
                    Text("Branch prefix: exp/\(previewSlug)/…")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if let error = prototypeViewModel.error {
                Text(error.localizedDescription)
                    .foregroundColor(.red)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("Create") { createIfValid() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(24)
        .frame(minWidth: 360, minHeight: 180)
        .onAppear {
            nameFieldFocused = true
            prototypeViewModel.error = nil
        }
    }

    private func createIfValid() {
        guard isValid else { return }
        prototypeViewModel.createPrototype(name: name)
        dismiss()
    }
}
