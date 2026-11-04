import AppKit
import BimeronModel
import SwiftUI
import UniformTypeIdentifiers

struct AddProfileView: View {
    @Bindable var model: AppModel
    var create: () -> Void = {}
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
    @State private var sshIdentityPath = ""
    @State private var sshKnownHostsPath = ""
    @State private var sshDefaults = (identity: "", knownHosts: "")

    private var validKey: Bool { Self.accepts(key) }
    private var isFile: Bool { ProfileInput.fileURL(key) != nil }
    private var isSSH: Bool { AccessProtocol(key: ProfileInput.normalized(key)) == .ssh }
    private var canSave: Bool { !busy && validKey && (isFile || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.t("Add profile")).font(.headline)
            if validKey && !isFile {
                Text(model.t("Profile name"))
                TextField(model.t("Profile name"), text: Binding(
                    get: { name },
                    set: { name = $0; nameEdited = true }
                ))
                    .textFieldStyle(.roundedBorder)
            }
            Text(model.t("Access link or configuration file"))
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

            HStack {
                Button(model.t("Browse…")) {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.begin { response in
                        if response == .OK, let url = panel.url { key = url.path }
                    }
                }
                Button(model.t("Create in editor")) { create() }
            }
            Text(model.t("Links and files receive local checks only. Use the editor to validate with Core."))
                .font(.caption).foregroundStyle(.secondary)
            if let clipboardKey {
                Button {
                    key = clipboardKey
                } label: {
                    Text(model.t("Paste key") + (Self.suggestedName(for: clipboardKey).map { " #\($0)" } ?? ""))
                        .frame(maxWidth: .infinity)
                }
            }

            if validKey && !isFile {
                LabeledContent(model.t("Protocol"), value: ConfigDocument.protocolName(for: ProfileInput.normalized(key)))
            }

            if isSSH {
                sshFilePicker("SSH known_hosts file (optional)", path: $sshKnownHostsPath, defaultPath: sshDefaults.knownHosts)
                sshFilePicker("SSH private key file (optional)", path: $sshIdentityPath, defaultPath: sshDefaults.identity)
            }

            if let issue { Text(issue).font(.subheadline).foregroundStyle(.red) }

            HStack {
                Spacer()
                Button {
                    guard canSave else { return }
                    busy = true
                    Task {
                        if await model.addInput(name: name, input: key, sshIdentityFile: isSSH ? Self.fileURL(for: sshIdentityPath) : nil,
                                           sshKnownHostsFile: isSSH ? Self.fileURL(for: sshKnownHostsPath) : nil) { dismiss() }
                        else {
                            issue = model.alertMessage
                            model.alertMessage = nil
                        }
                        busy = false
                    }
                } label: {
                    Text(model.t("Save"))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(AppPalette.blue.opacity(canSave ? 1 : 0.5), in: .rect(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
                Button(model.t("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .frame(minWidth: 560, idealWidth: 640, maxWidth: 800)
        .background(AppPalette.surface(colorScheme))
        .onAppear {
            sshDefaults = Self.defaultSSHPaths(in: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".ssh"))
            keyFocused = true
            refreshClipboard()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            refreshClipboard()
        }
    }

    static func accepts(_ value: String) -> Bool {
        let key = ProfileInput.normalized(value)
        if ProfileInput.fileURL(key) != nil { return true }
        return (try? ConfigDocument.validateKey(key)) != nil
    }

    static func fileURL(for path: String) -> URL? {
        let path = ProfileInput.normalized(path)
        guard !path.isEmpty else { return nil }
        if let url = URL(string: path), url.isFileURL { return url }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    static func defaultSSHPaths(in directory: URL) -> (identity: String, knownHosts: String) {
        func existingPath(_ names: [String]) -> String {
            for name in names {
                let url = directory.appending(path: name)
                if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    return url.path
                }
            }
            return ""
        }
        return (existingPath(["id_ed25519", "id_ecdsa", "id_rsa"]), existingPath(["known_hosts"]))
    }

    private func sshFilePicker(_ title: String, path: Binding<String>, defaultPath: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.t(title))
            HStack {
                TextField(defaultPath.isEmpty ? model.t("File path") : defaultPath, text: path)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(model.t(title))
                    .onPasteCommand(of: [.fileURL]) { providers in
                        guard let provider = providers.first else { return }
                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                            let url = (item as? URL) ?? (item as? Data).flatMap {
                                URL(dataRepresentation: $0, relativeTo: nil)
                            }
                            guard let url, url.isFileURL else { return }
                            Task { @MainActor in path.wrappedValue = url.path }
                        }
                    }
                if path.wrappedValue.isEmpty, !defaultPath.isEmpty {
                    Button(model.t("Use default")) { path.wrappedValue = defaultPath }
                }
                Button(model.t("Choose file…")) { chooseSSHFile(path) }
                if !path.wrappedValue.isEmpty {
                    Button(model.t("Remove")) { path.wrappedValue = "" }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.t(title))
    }

    private func chooseSSHFile(_ path: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".ssh", directoryHint: .isDirectory)
        panel.begin { response in
            if response == .OK, let url = panel.url { path.wrappedValue = url.path }
        }
    }

    private static func suggestedName(for value: String) -> String? {
        let value = ProfileInput.normalized(value)
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
