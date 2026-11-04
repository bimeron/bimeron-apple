import BimeronModel
import SwiftUI

struct EditorView: View {
    @Bindable var model: AppModel
    let profile: StoredProfile
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var document: ConfigDocument
    @State private var rawText: String
    @State private var tab: EditorTab
    @State private var issue: String?
    @State private var busy = false
    @State private var revealKey = false
    @State private var selectedRule: Int?
    @State private var confirmCancel = false

    init(model: AppModel, profile: StoredProfile) {
        self.model = model
        self.profile = profile
        _document = State(initialValue: profile.document)
        _rawText = State(initialValue: profile.document.text)
        _tab = State(initialValue: profile.document.formEditingIssue == nil ? .general : .raw)
        _issue = State(initialValue: profile.document.formEditingIssue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.t("Profile settings")).font(.title2.bold())
            HStack(spacing: 16) {
                ForEach(EditorTab.allCases, id: \.self) { item in
                    Button(model.t(item.title)) { switchTo(item) }
                        .buttonStyle(.plain)
                        .foregroundStyle(tab == item ? Color.accentColor : .secondary)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            if tab == item { Rectangle().fill(Color.accentColor).frame(height: 2) }
                        }
                }
            }
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let issue { Text(issue).foregroundStyle(.red).font(.subheadline).lineLimit(2) }
            HStack {
                Text(model.t("Only basic checks are available. Core validation and connections are not integrated."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(model.t("Cancel")) {
                    if rawText != profile.document.text { confirmCancel = true } else { dismiss() }
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
            LabeledContent(model.t("Protocol"), value: document.protocolName)
            if !document.isExplicit && (AccessProtocol(rawValue: document.source) != nil || document.source == "Key") {
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
            if let protocolType = document.accessProtocol {
                if document.isExplicit {
                    ForEach(ProtocolField.fields(for: protocolType)) { item in
                        protocolField(item)
                    }
                    if document.value("AccessKey", "Type") == "https" {
                        field("Server name (SNI)", "AccessKey", "ServerName")
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
            if canAddShadowTLS || document.hasShadowTLSDraft {
                Section("ShadowTLS v3") {
                    Toggle(model.t("Enable ShadowTLS wrapper"), isOn: shadowTLSBinding)
                    if document.hasShadowTLSDraft {
                        field("Server name (SNI)", "ShadowTLS", "ServerName")
                        secureField("Password", "ShadowTLS", "Password")
                    }
                    Text(model.t("ShadowTLS requires a compatible encrypted TCP upstream. Core must validate the combination."))
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
        guard let protocolType = document.accessProtocol else { return false }
        return [.shadowsocks, .dynamicShadowsocks, .vless, .vmess, .trojan, .anytls, .naive, .ssh].contains(protocolType)
    }

    private var shadowTLSBinding: Binding<Bool> {
        Binding(get: { document.shadowTLSEnabled }, set: { enabled in
            document.setShadowTLSEnabled(enabled)
            rawText = document.text
            issue = nil
        })
    }

    @ViewBuilder private func protocolField(_ item: ProtocolField) -> some View {
        if item.file {
            fileField(item.title, item.id)
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
                    if response == .OK, let url = panel.url {
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
            Table(document.rules, selection: $selectedRule) {
                TableColumn(model.t("On")) { rule in
                    Toggle("", isOn: ruleBinding(rule.id, \.enabled)).labelsHidden()
                }.width(50)
                TableColumn(model.t("Type")) { rule in
                    Picker("", selection: ruleBinding(rule.id, \.type)) {
                        Text("CIDR").tag("CIDR")
                        Text("Domain").tag("Domain")
                    }.labelsHidden()
                }.width(105)
                TableColumn(model.t("Destination")) { rule in
                    TextField("", text: ruleBinding(rule.id, \.destination))
                }
                TableColumn(model.t("Action")) { rule in
                    Picker("", selection: ruleBinding(rule.id, \.action)) {
                        Text(model.t("Via VPN")).tag("proxy")
                        Text(model.t("Direct")).tag("direct")
                        Text(model.t("Block")).tag("block")
                    }.labelsHidden()
                }.width(120)
            }
            HStack {
                Button(model.t("Add")) { document.addRule(); rawText = document.text }
                Button(model.t("Remove")) {
                    if let selectedRule { document.removeRule(selectedRule); self.selectedRule = nil; rawText = document.text }
                }.disabled(selectedRule == nil)
                Button(model.t("Move up")) { moveRule(-1) }.disabled(selectedRule == nil || selectedRule == 0)
                Button(model.t("Move down")) { moveRule(1) }.disabled(selectedRule == nil || selectedRule == document.rules.count - 1)
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
            ConfigTextEditor(text: $rawText)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.secondary.opacity(0.3)))
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

    private func ruleBinding<T>(_ id: Int, _ keyPath: WritableKeyPath<RoutingRule, T>) -> Binding<T> {
        Binding(get: { document.rules[id][keyPath: keyPath] }, set: { value in
            guard document.rules.indices.contains(id) else { return }
            var rule = document.rules[id]
            rule[keyPath: keyPath] = value
            document.updateRule(rule)
            rawText = document.text
        })
    }

    private func switchTo(_ target: EditorTab) {
        if tab == .raw && target != .raw {
            do {
                let parsed = try ConfigDocument(rawText)
                if let reason = parsed.formEditingIssue { issue = model.t(reason); return }
                document = parsed
                selectedRule = nil
                issue = nil
            }
            catch { issue = model.t("Fix the raw config before switching to the form"); return }
        }
        tab = target
    }

    private func moveRule(_ offset: Int) {
        guard let selectedRule else { return }
        document.moveRule(selectedRule, by: offset)
        self.selectedRule = selectedRule + offset
        rawText = document.text
    }

    private func save() {
        do {
            let parsed = try ConfigDocument(rawText)
            try parsed.validateLocally()
            busy = true
            Task {
                let ok = await model.save(StoredProfile(id: profile.id, document: parsed))
                busy = false
                if ok { dismiss() }
                else {
                    issue = model.alertMessage
                    model.alertMessage = nil
                }
            }
        } catch {
            model.report(error)
            issue = model.alertMessage
            model.alertMessage = nil
        }
    }
}
