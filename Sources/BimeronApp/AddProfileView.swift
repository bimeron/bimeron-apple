import AppKit
import BimeronModel
import SwiftUI

struct AddProfileView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @FocusState private var keyFocused: Bool
    @State private var name = ""
    @State private var key = ""
    @State private var nameEdited = false
    @State private var busy = false
    @State private var issue: String?
    @State private var clipboardKey: String?
    @State private var pasteboardChangeCount = -1

    private var validKey: Bool { Self.accepts(key) }
    private var canSave: Bool { !busy && validKey && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.t("Add profile")).font(.headline)
            Text(model.t("Paste an access link"))
            Text(model.t("Supported protocols") + ": " + AccessProtocol.allCases.map(\.title).joined(separator: ", "))
                .font(.caption).foregroundStyle(.secondary)
            TextField(model.t("Access key"), text: $key)
                .textFieldStyle(.roundedBorder)
                .focused($keyFocused)
                .onChange(of: key) { _, value in
                    issue = nil
                    guard !nameEdited else { return }
                    name = Self.suggestedName(for: value) ?? ""
                }

            if let clipboardKey {
                Button {
                    key = clipboardKey
                } label: {
                    Text(model.t("Paste key") + (Self.suggestedName(for: clipboardKey).map { " #\($0)" } ?? ""))
                        .frame(maxWidth: .infinity)
                }
            }

            if validKey {
                LabeledContent(model.t("Protocol"), value: ConfigDocument.protocolName(for: key.trimmingCharacters(in: .whitespacesAndNewlines)))
                Text(model.t("Profile name"))
                TextField(model.t("Profile name"), text: Binding(
                    get: { name },
                    set: { name = $0; nameEdited = true }
                ))
                    .textFieldStyle(.roundedBorder)
            }

            if let issue { Text(issue).font(.subheadline).foregroundStyle(.red) }

            HStack {
                Spacer()
                Button {
                    guard canSave else { return }
                    busy = true
                    Task {
                        if await model.add(name: name, key: key) { dismiss() }
                        else {
                            issue = model.alertMessage
                            model.alertMessage = nil
                        }
                        busy = false
                    }
                } label: {
                    Text(model.t("Save"))
                }
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.blue)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
                Button(model.t("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .frame(width: 493)
        .background(AppPalette.surface(colorScheme))
        .onAppear {
            keyFocused = true
            refreshClipboard()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            refreshClipboard()
        }
    }

    static func accepts(_ value: String) -> Bool {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return (try? ConfigDocument.validateKey(key)) != nil
    }

    private static func suggestedName(for value: String) -> String? {
        guard !value.lowercased().hasPrefix("socks5://") else { return nil }
        return ConfigDocument.suggestedName(for: value)
    }

    private func refreshClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != pasteboardChangeCount else { return }
        pasteboardChangeCount = pasteboard.changeCount
        if let value = pasteboard.string(forType: .string), Self.accepts(value) {
            clipboardKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            clipboardKey = nil
        }
    }
}
