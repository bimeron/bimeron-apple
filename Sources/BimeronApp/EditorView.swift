import BimeronModel
import SwiftUI

struct EditorView: View {
    @Bindable var model: AppModel
    let profile: StoredProfile
    let creating: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var document: ConfigDocument
    @State private var rawText: String
    @State private var tab: EditorTab
    @State private var issue: String?
    @State private var busy = false
    @State private var saveTask: Task<Void, Never>?
    @State private var revealKey = false
    @State private var routingEditing = RoutingRuleEditingState()
    @State private var confirmCancel = false
    @State private var drafts: ProtocolDrafts
    private var creationProtocol: EditorProtocol { drafts.selected }

    init(model: AppModel, profile: StoredProfile, creating: Bool = false) {
        self.creating = creating
        self.model = model
        self.profile = profile
        _drafts = State(initialValue: ProtocolDrafts(creationDocument: creating ? profile.document : nil))
        _document = State(initialValue: profile.document)
        _rawText = State(initialValue: profile.document.text)
        _tab = State(initialValue: profile.document.formEditingIssue == nil ? (creating ? .upstream : .general) : .raw)
        _issue = State(initialValue: profile.document.formEditingIssue.map { model.t($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.t("Profile settings")).font(.title2.bold())
            HStack(spacing: 16) {
                ForEach(EditorTab.allCases, id: \.self) { item in
                    Button(model.t(item.title)) { switchTo(item) }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(tab == item ? .isSelected : [])
                        .foregroundStyle(tab == item ? Color.accentColor : .secondary)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            if tab == item { Rectangle().fill(Color.accentColor).frame(height: 2) }
                        }
                }
            }
            .disabled(busy)
            Divider()

            Group {
                switch tab {
                case .general: general
                case .upstream: upstream
                case .network: network
                case .routing: routing
                case .raw: raw
                }
            }
            .disabled(busy)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let issue { Text(issue).foregroundStyle(.red).font(.subheadline).lineLimit(2) }
            HStack {
                Text(model.t("Core validates saved configurations. Live connections are not checked."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(model.t("Cancel")) {
                    saveTask?.cancel()
                    if drafts.hasEdits || rawText != profile.document.text { confirmCancel = true } else { dismiss() }
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    guard !busy else { return }
                    save()
                } label: {
                    Text(model.t("Save"))
                }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.blue)
                    .disabled(busy)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(minWidth: 680, minHeight: 520)
        .frame(idealWidth: 760, idealHeight: 600)
        .background(AppPalette.surface(colorScheme))
        .onDisappear { saveTask?.cancel() }
        .onChange(of: rawText) { _, value in
            if value != profile.document.text { drafts.recordEdits() }
        }
        .confirmationDialog(model.t("Discard changes?"), isPresented: $confirmCancel) {
            Button(model.t("Discard changes"), role: .destructive) { dismiss() }
            Button(model.t("Keep editing"), role: .cancel) {}
        }
    }

    private var general: some View {
        Form {
            field("Name", "Profile", "Name")
            LabeledContent(model.t("Key source")) { Text(document.source).foregroundStyle(.secondary) }
            LabeledContent(model.t("Protocol"), value: document.protocolName)
            Picker(model.t("Mode"), selection: fieldBinding("Interface", "Mode")) {
                Text(model.t("System VPN")).tag("vpn")
                Text(model.t("Local proxy")).tag("proxy")
            }
            if document.mode == "proxy" { field("SOCKS5 address", "Interface", "Listen") }
        }
        .formStyle(.grouped)
    }

    private var upstream: some View {
        Form {
            if creating {
                Picker(model.t("Protocol"), selection: Binding(get: { creationProtocol }, set: { changeProtocol($0) })) {
                    ForEach(EditorProtocol.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Text(model.t("Each protocol keeps its own draft when you switch."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent(model.t("Protocol"), value: document.protocolName)
            if creating && creationProtocol.generated {
                ForEach(creationProtocol.fields, id: \.self) { key in
                    if let choices = ProtocolField.generated(key).choices {
                        Picker(model.t(ProtocolField.generated(key).title), selection: generatedBinding(key)) {
                            ForEach(choices, id: \.self) { Text($0.isEmpty ? model.t("Use default") : $0).tag($0) }
                        }
                    } else if ProtocolField.generated(key).secret {
                        SecureField(model.t(ProtocolField.generated(key).title), text: generatedBinding(key))
                    } else {
                        TextField(model.t(ProtocolField.generated(key).title), text: generatedBinding(key), prompt: key == "Port" ? Text(creationProtocol.defaultPort) : nil)
                    }
                }
            }
            if !(creating && creationProtocol.generated) && !document.isExplicit && (AccessProtocol(rawValue: document.source) != nil || document.source == "Key") {
                Section(model.t("Access key")) {
                    if revealKey {
                        TextField(model.t("Link"), text: fieldBinding("AccessKey", document.source), axis: .vertical)
                            .lineLimit(3...6)
                    } else {
                        SecureField(model.t("Link"), text: fieldBinding("AccessKey", document.source))
                    }
                    Toggle(model.t("Show access key"), isOn: $revealKey)
                    Text(model.t("The complete link is preserved, including transport and security parameters."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !document.vlessInspection.isEmpty {
                Section(model.t("Decoded VLESS (read-only)")) {
                    ForEach(Array(document.vlessInspection.enumerated()), id: \.offset) { _, pair in
                        LabeledContent(model.t(pair.0), value: revealKey || ["Server", "Port", "type", "security", "encryption", "flow", "alpn"].contains(pair.0) ? pair.1 : "••••••••")
                    }
                }
            }
            if let protocolType = document.accessProtocol {
                if document.isExplicit {
                    ForEach(ProtocolField.fields(for: protocolType)) { item in
                        protocolField(item)
                    }
                }
                if protocolType == .ssh {
                    fileField("SSH identity file", "IdentityFile")
                    fileField("SSH known_hosts file", "KnownHostsFile")
                    Text(model.t("SSH requires a trusted known_hosts entry. Password prompts will be available after Core integration."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let notice = protocolNotice {
                    Text(model.t(notice)).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let compatibility = document.editorCompatibilityIssue {
                Text(model.t(compatibility)).font(.caption).foregroundStyle(.red)
            }
            if document.isExplicit && document.accessProtocol == .vless {
                Text(model.t("Vision requires TCP with REALITY. Keep transport-specific fields compatible; inactive values are retained and Core rejects conflicts."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if document.isExplicit && document.accessProtocol == .shadowsocks {
                Text(model.t("SS2022 requires a base64 key of the cipher's exact length. Prefix and plugin options are preserved; plugins cannot wrap ShadowTLS."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if canAddShadowTLS || document.hasShadowTLSDraft {
                Section("ShadowTLS v3") {
                    Toggle(model.t("Enable ShadowTLS wrapper"), isOn: shadowTLSBinding)
                        .disabled(!canAddShadowTLS && !document.shadowTLSEnabled)
                    if document.hasShadowTLSDraft {
                        field("Server name (SNI)", "ShadowTLS", "ServerName")
                        secureField("Password", "ShadowTLS", "Password")
                    }
                    Text(model.t("Use the outer ShadowTLS listener host and port as the upstream endpoint. Wrapper password and SNI are independent of inner credentials. ShadowTLS does not replace inner encryption or certificate verification, provide native UDP, or change stream policy. ShadowTLS excludes SS plugins, aes-192-gcm, unencrypted VLESS and HTTP/3. Core checks URI details and compatibility."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var protocolNotice: String? {
        switch document.accessProtocol {
        case .ssh, .http, .naive:
            "TCP-only upstream: in VPN mode, DNS uses TCP and other proxied UDP is dropped."
        case .hysteria2:
            "Hysteria2 UDP relay depends on server permissions. QUIC fingerprint options stay in the link."
        case .tuic:
            "TUIC v5 supports stream-mode UDP relay; QUIC datagram mode is not supported."
        case .dynamicShadowsocks:
            "Dynamic keys are fetched by Core at start or reconnect, not periodically during a healthy connection."
        case .shadowsocks:
            "Shadowsocks plugins are TCP-only. SS2022 key lengths and plugin compatibility require Core validation."
        case .vless:
            "VLESS supports TCP, WebSocket, gRPC and XHTTP. Extended XHTTP settings can remain in the link or raw config."
        case .vmess:
            "VMess AEAD settings are stored in the complete vmess:// link, including its encoded JSON."
        default: nil
        }
    }

    private var canAddShadowTLS: Bool {
        document.shadowTLSCompatibilityIssue == nil
    }

    private var shadowTLSBinding: Binding<Bool> {
        Binding(get: { document.shadowTLSEnabled }, set: { enabled in
            document.setShadowTLSEnabled(enabled)
            rawText = document.text
            issue = nil
        })
    }

    @ViewBuilder private func protocolField(_ item: ProtocolField) -> some View {
        if creating && item.id == "Port" && document.value("AccessKey", "Type") == creationProtocol.type {
            TextField(model.t(item.title), text: Binding(
                get: { drafts.portValue(in: document) },
                set: { value in
                    document = drafts.setPort(value, in: document)
                    rawText = document.text
                    issue = nil
                }
            ), prompt: Text(creationProtocol.defaultPort))
        } else if item.file {
            fileField(item.title, item.id)
        } else if let choices = item.choices {
            Picker(model.t(item.title), selection: fieldBinding("AccessKey", item.id)) {
                let current = document.value("AccessKey", item.id) ?? ""
                if !choices.contains(current) { Text(current).tag(current) }
                ForEach(choices, id: \.self) { Text($0.isEmpty ? model.t("Default") : $0).tag($0) }
            }
        } else if item.secret {
            secureField(item.title, "AccessKey", item.id)
        } else {
            field(item.title, "AccessKey", item.id)
        }
    }

    private func fileField(_ title: String, _ key: String) -> some View {
        HStack {
            field(title, "AccessKey", key)
            Button(model.t("Choose file…")) {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                panel.begin { response in
                    if !busy, response == .OK, let url = panel.url {
                        document.set("AccessKey", key, url.path)
                        rawText = document.text
                        issue = nil
                    }
                }
            }
            .accessibilityLabel(model.t("Choose file…") + " " + model.t(title))
        }
    }

    private var network: some View {
        Form {
            if document.mode == "vpn" {
                field("Interface name", "Interface", "Name")
                field("MTU", "Interface", "MTU")
                Picker("IPv6", selection: fieldBinding("Interface", "IPv6")) {
                    Text(model.t("Enabled")).tag("enable")
                    Text(model.t("Disabled")).tag("disable")
                }
                Toggle(model.t("Block traffic outside VPN"), isOn: .constant(document.value("Interface", "KillSwitch") == "true")).disabled(true)
                Text(model.t("Kill switch is not available on macOS yet"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(model.t("On macOS, the system assigns utunN; the interface name is a logical label."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                field("SOCKS5 address", "Interface", "Listen")
                Text(model.t("Tunnel interface, MTU and IPv6 controls apply to VPN mode only."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            field("DNS (up to four IPv4 addresses)", "Interface", "DNS")
        }
        .formStyle(.grouped)
    }

    private var routing: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker(model.t("Default action"), selection: fieldBinding("Routing", "Default")) {
                    Text(model.t("Via VPN")).tag("proxy")
                    Text(model.t("Direct")).tag("direct")
                    Text(model.t("Block")).tag("block")
                }.frame(width: 280)
                Spacer()
            }
            Table(document.rules, selection: $routingEditing.selection) {
                TableColumn(model.t("On")) { rule in
                    Toggle(ruleLabel("On", rule.id), isOn: ruleBinding(rule, \.enabled)).labelsHidden()
                }.width(50)
                TableColumn(model.t("Type")) { rule in
                    Picker(ruleLabel("Type", rule.id), selection: ruleBinding(rule, \.type)) {
                        Text("CIDR").tag("CIDR")
                        Text(model.t("Domain")).tag("Domain")
                    }.labelsHidden()
                }.width(105)
                TableColumn(model.t("Destination")) { rule in
                    TextField(ruleLabel("Destination", rule.id), text: ruleBinding(rule, \.destination))
                }
                TableColumn(model.t("Action")) { rule in
                    Picker(ruleLabel("Action", rule.id), selection: ruleBinding(rule, \.action)) {
                        Text(model.t("Via VPN")).tag("proxy")
                        Text(model.t("Direct")).tag("direct")
                        Text(model.t("Block")).tag("block")
                    }.labelsHidden()
                }.width(120)
            }
            .id(routingEditing.generation)
            HStack {
                Button(model.t("Add")) { routingEditing.add(to: &document); rawText = document.text }
                Button(model.t("Remove")) {
                    routingEditing.remove(from: &document); rawText = document.text
                }.disabled(routingEditing.selection == nil)
                Button(model.t("Move up")) { moveRule(-1) }.disabled(routingEditing.selection == nil || routingEditing.selection == 0)
                Button(model.t("Move down")) { moveRule(1) }.disabled(routingEditing.selection == nil || routingEditing.selection == document.rules.count - 1)
            }
            Text(model.t("Rules are applied from top to bottom: first match wins."))
                .font(.caption).foregroundStyle(.secondary)
            Text(model.t("VPN domain rules depend on Core-observed DNS. DoH, cached DNS and direct IP connections may not match them."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var raw: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.t("Raw profile text. Fields not shown in the form are preserved."))
                .font(.subheadline).foregroundStyle(.secondary)
            if creating && creationProtocol.generated {
                Button(model.t("Restore generated access key")) {
                    do {
                        let parsed = try drafts.restoringGeneratedSource(in: ConfigDocument(rawText))
                        routingEditing.acceptRaw(parsed, replacing: &document)
                        rawText = parsed.text
                        issue = parsed.accessKey.isEmpty ? model.t("Enter a server and a valid port") : nil
                    } catch ProfileError.invalid("GeneratedAccessKey") {
                        issue = model.t("Keep edited generated links in Raw, or restore the parameter draft before switching.")
                    } catch { showGenerationError(error) }
                }
            }
            ConfigTextEditor(text: $rawText, accessibilityLabel: model.t("Raw profile text"))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.secondary.opacity(0.3)))
        }
    }

    private func ruleLabel(_ title: String, _ id: Int) -> String {
        model.t("Rule") + " " + String(id + 1) + ", " + model.t(title)
    }

    private func changeProtocol(_ target: EditorProtocol) {
        do {
            let parsed = try ConfigDocument(rawText)
            if let reason = parsed.formEditingIssue { issue = model.t(reason); return }
            let next = try drafts.select(target, current: parsed)
            routingEditing.acceptRaw(next, replacing: &document)
            rawText = document.text
            issue = nil
        } catch ProfileError.invalid("GeneratedAccessKey") {
            issue = model.t("Keep edited generated links in Raw, or restore the parameter draft before switching.")
        } catch { issue = model.t("Fix the raw config before switching to the form") }
    }

    private func generatedBinding(_ key: String) -> Binding<String> {
        Binding(get: { drafts.value(key) }, set: { value in
            do {
                let generated = try drafts.set(key, value: value, name: document.name)
                document.set("AccessKey", generated.source, generated.accessKey)
                rawText = document.text
                issue = generated.accessKey.isEmpty ? model.t("Enter a server and a valid port") : nil
            } catch { showGenerationError(error) }
        })
    }

    private func showGenerationError(_ error: Error) {
        if case ProfileError.invalid(let field) = error {
            issue = model.t("Check field") + ": " + model.t(field)
        } else {
            issue = error.localizedDescription
        }
    }

    private func field(_ title: String, _ section: String, _ key: String) -> some View {
        TextField(model.t(title), text: fieldBinding(section, key))
    }

    private func secureField(_ title: String, _ section: String, _ key: String) -> some View {
        SecureField(model.t(title), text: fieldBinding(section, key))
    }

    private func fieldBinding(_ section: String, _ key: String) -> Binding<String> {
        Binding(get: {
            if section == "ShadowTLS" { return document.shadowTLSValue(key) ?? "" }
            if let value = document.value(section, key) { return value }
            switch (section, key) {
            case ("Interface", "Mode"): return "vpn"
            case ("Interface", "IPv6"): return "enable"
            case ("Routing", "Default"): return "proxy"
            default: return ""
            }
        }, set: { value in
            let isAccessSource = section == "AccessKey" && (AccessProtocol(rawValue: key) != nil || key == "Key")
            if section == "ShadowTLS" { document.setShadowTLSValue(key, value) }
            else if section == "Interface", key == "Mode" { document.setMode(value) }
            else if value.isEmpty && !isAccessSource { document.remove(section, key) }
            else { document.set(section, key, value) }
            rawText = document.text
            issue = nil
        })
    }

    private func ruleBinding<T>(_ rule: RoutingRule, _ keyPath: WritableKeyPath<RoutingRule, T>) -> Binding<T> {
        let snapshot = routingEditing.snapshot(rule)
        return Binding(get: {
            snapshot.read(from: document, state: routingEditing)[keyPath: keyPath]
        }, set: { value in
            snapshot.write(value, at: keyPath, to: &document, state: routingEditing)
            rawText = document.text
        })
    }

    private func switchTo(_ target: EditorTab) {
        if tab == .raw && target != .raw {
            do {
                let parsed = try ConfigDocument(rawText)
                if creating { try drafts.checkParameterSource(parsed) }
                if let reason = parsed.formEditingIssue { issue = model.t(reason); return }
                if creating { drafts.acceptRawPort(in: parsed, previous: document) }
                routingEditing.acceptRaw(parsed, replacing: &document)
                issue = nil
            }
            catch ProfileError.invalid("GeneratedAccessKey") {
                issue = model.t("Keep edited generated links in Raw, or restore the parameter draft before switching.")
                return
            }
            catch { issue = model.t("Fix the raw config before switching to the form"); return }
        }
        tab = target
    }

    private func moveRule(_ offset: Int) {
        routingEditing.move(in: &document, by: offset)
        rawText = document.text
    }

    private func save() {
        do {
            let parsed = try ConfigDocument(rawText)
            if tab != .raw, let compatibility = parsed.editorCompatibilityIssue {
                issue = model.t(compatibility)
                return
            }
            if creating { try drafts.checkSave(parsed, raw: tab == .raw) }
            else { try parsed.validateLocally() }
            busy = true
            saveTask = Task {
                let ok = creating ? await model.create(parsed) : await model.save(StoredProfile(id: profile.id, document: parsed), original: profile)
                busy = false
                // A committed save remains successful even if cancellation arrives during reload.
                if ok { dismiss() }
                else {
                    issue = model.alertMessage
                    model.alertMessage = nil
                }
            }
        } catch ProfileError.invalid("GeneratedAccessKey") {
            issue = model.t("Keep edited generated links in Raw, or restore the parameter draft before switching.")
        } catch {
            model.report(error)
            issue = model.alertMessage
            model.alertMessage = nil
        }
    }
}

// Position-based rule IDs are valid only within one structural generation.
struct RoutingRuleEditingState {
    private(set) var generation = UUID()
    var selection: Int?

    func snapshot(_ rule: RoutingRule) -> RoutingRuleEditingSnapshot {
        RoutingRuleEditingSnapshot(rule: rule, generation: generation)
    }

    mutating func add(to document: inout ConfigDocument) {
        guard document.formEditingIssue == nil else { return }
        document.addRule()
        generation = UUID()
        selection = document.rules.count - 1
    }

    mutating func remove(from document: inout ConfigDocument) {
        guard document.formEditingIssue == nil, let selection,
              document.rules.indices.contains(selection) else { return }
        document.removeRule(selection)
        generation = UUID()
        self.selection = nil
    }

    mutating func move(in document: inout ConfigDocument, by offset: Int) {
        guard document.formEditingIssue == nil, let selection,
              offset == -1 || offset == 1, document.rules.indices.contains(selection) else { return }
        let other = selection.addingReportingOverflow(offset)
        guard !other.overflow, document.rules.indices.contains(other.partialValue) else { return }
        document.moveRule(selection, by: offset)
        generation = UUID()
        self.selection = other.partialValue
    }

    mutating func acceptRaw(_ parsed: ConfigDocument, replacing document: inout ConfigDocument) {
        if parsed.text != document.text {
            generation = UUID()
            selection = nil
        }
        document = parsed
    }
}

struct RoutingRuleEditingSnapshot {
    let rule: RoutingRule
    let generation: UUID

    func read(from document: ConfigDocument, state: RoutingRuleEditingState) -> RoutingRule {
        guard generation == state.generation else { return rule }
        return document.rules.first { $0.id == rule.id } ?? rule
    }

    func write<T>(_ value: T, at keyPath: WritableKeyPath<RoutingRule, T>,
                  to document: inout ConfigDocument, state: RoutingRuleEditingState) {
        guard generation == state.generation, document.formEditingIssue == nil,
              var current = document.rules.first(where: { $0.id == rule.id }) else { return }
        current[keyPath: keyPath] = value
        document.updateRule(current)
    }
}
