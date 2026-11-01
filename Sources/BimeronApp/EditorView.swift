import BimeronModel
import SwiftUI

struct EditorView: View {
    @Bindable var model: AppModel
    let profile: StoredProfile
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var document: ConfigDocument
    @State private var rawText: String
    @State private var tab: EditorTab = .general
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
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.t("Profile settings")).font(.title2.bold())
            HStack(spacing: 16) {
                ForEach(EditorTab.allCases.filter { $0 != .vless || document.protocolName == "VLESS" }, id: \.self) { item in
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
                case .vless: vless
                case .network: network
                case .routing: routing
                case .raw: raw
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let issue { Text(issue).foregroundStyle(.red).font(.subheadline).lineLimit(2) }
            HStack {
                Text(model.t("Core validation will be added with VPN support"))
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
                    Text(model.t("Save")).foregroundStyle(.white)
                }
                    .buttonStyle(.borderedProminent)
                    .tint(busy ? AppPalette.blueDisabledButton : AppPalette.blue)
                    .allowsHitTesting(!busy)
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
            LabeledContent(model.t("Link")) {
                HStack {
                    if revealKey { Text(document.accessKey).lineLimit(1).textSelection(.enabled) }
                    else { Text("••••••••••••").foregroundStyle(.secondary) }
                    Spacer()
                    Button(revealKey ? model.t("Hide") : model.t("Show")) { revealKey.toggle() }
                }
            }
            Picker(model.t("Mode"), selection: fieldBinding("Interface", "Mode")) {
                Text(model.t("System VPN")).tag("vpn")
                Text(model.t("Local proxy")).tag("proxy")
            }
            if document.source == "explicit" || ["shadowsocks", "socks5", "vless", "trojan"].contains(document.source) {
                field("Server", "AccessKey", "Server")
                field("Port", "AccessKey", "Port")
                field("Encryption", "AccessKey", "Method")
                field("Username", "AccessKey", "Username")
                secureField("Password", "AccessKey", "Password")
                field("Prefix", "AccessKey", "Prefix")
            }
            if document.mode == "proxy" { field("SOCKS5 address", "Interface", "Listen") }
        }
        .formStyle(.grouped)
    }

    private var vless: some View {
        ScrollView {
            Form {
                if document.protocolName == "VLESS" {
                    Text(model.t("URI parameters are shown in the raw config. Edit the VLESS URI there."))
                        .foregroundStyle(.secondary)
                    if document.source == "VLESS" || document.source == "Key" {
                        ForEach(Array(document.vlessDetails.enumerated()), id: \.offset) { _, item in
                            LabeledContent(item.0) { Text(item.1).textSelection(.enabled) }
                        }
                    }
                    if document.source == "vless" {
                        field("Server", "AccessKey", "Server")
                        field("Port", "AccessKey", "Port")
                        field("User ID", "AccessKey", "ID")
                        field("Encryption", "AccessKey", "Encryption")
                        field("Transport", "AccessKey", "Network")
                        field("Security", "AccessKey", "Security")
                        field("Flow", "AccessKey", "Flow")
                        field("Server name (SNI)", "AccessKey", "ServerName")
                        field("REALITY public key", "AccessKey", "PublicKey")
                        field("REALITY short ID", "AccessKey", "ShortID")
                        field("SpiderX", "AccessKey", "SpiderX")
                        field("Client fingerprint", "AccessKey", "Fingerprint")
                        field("ALPN", "AccessKey", "ALPN")
                        field("WebSocket path", "AccessKey", "WSPath")
                        field("WebSocket host", "AccessKey", "WSHost")
                        field("WebSocket early data", "AccessKey", "WSEarlyData")
                        field("gRPC service", "AccessKey", "GRPCServiceName")
                        field("gRPC host", "AccessKey", "GRPCAuthority")
                        field("gRPC multi mode", "AccessKey", "GRPCMultiMode")
                        field("XHTTP mode", "AccessKey", "XHTTPMode")
                        field("XHTTP path", "AccessKey", "XHTTPPath")
                        field("XHTTP host", "AccessKey", "XHTTPHost")
                        field("XHTTP extra", "AccessKey", "XHTTPExtra")
                    }
                } else {
                    ContentUnavailableView(model.t("This profile does not use VLESS"), systemImage: "network")
                }
            }
            .formStyle(.grouped)
        }
    }

    private var network: some View {
        Form {
            field("Interface name", "Interface", "Name")
            field("MTU", "Interface", "MTU")
            field("DNS (up to four IPv4 addresses)", "Interface", "DNS")
            Picker("IPv6", selection: fieldBinding("Interface", "IPv6")) {
                Text(model.t("Enabled")).tag("enable")
                Text(model.t("Disabled")).tag("disable")
            }
            Toggle(model.t("Block traffic outside VPN"), isOn: .constant(document.value("Interface", "KillSwitch") == "true")).disabled(true)
            Text(model.t("Kill switch is not available on macOS yet"))
                .font(.caption).foregroundStyle(.secondary)
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
            if let value = document.value(section, key) { return value }
            switch (section, key) {
            case ("Interface", "Mode"): return "vpn"
            case ("Interface", "IPv6"): return "enable"
            case ("Routing", "Default"): return "proxy"
            default: return ""
            }
        }, set: { value in
            document.set(section, key, value)
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
            do { document = try ConfigDocument(rawText); issue = nil }
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
