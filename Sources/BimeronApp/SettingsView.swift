import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var model: AppModel
    let quit: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var showDiagnosticsExport = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(model.t("Settings"))
                    .font(.system(size: 24, weight: .bold))
                Text(model.t("Application behavior, auto-connect, and Bimeron maintenance."))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 16) {
                    Text(model.t("Application")).font(.headline)
                    HStack {
                        Text(model.t("Theme"))
                        Spacer()
                        Picker(model.t("Theme"), selection: $model.theme) {
                            Text(model.t("System")).tag("system")
                            Text(model.t("Light")).tag("light")
                            Text(model.t("Dark")).tag("dark")
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }
                    HStack {
                        Text(model.t("Language"))
                        Spacer()
                        Picker(model.t("Language"), selection: $model.language) {
                            Text("English").tag("en")
                            Text(model.t("Russian")).tag("ru")
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }
                    Toggle(model.t("Disconnect VPN and stop the core service on quit"), isOn: .constant(false))
                        .disabled(true)
                    Toggle(model.t("Show system notifications"), isOn: .constant(true))
                        .disabled(true)
                    Toggle(model.t("Show detailed connection statistics"), isOn: .constant(false))
                        .disabled(true)
                    HStack {
                        Toggle(model.t("Connect automatically on launch"), isOn: .constant(false))
                            .disabled(true)
                        Picker(model.t("Auto-connect profile"), selection: .constant(model.profiles.first?.id)) {
                            Text(model.t("Select a profile")).tag(UUID?.none)
                            ForEach(model.profiles) { profile in
                                Text(profile.document.name).tag(Optional(profile.id))
                            }
                        }
                        .labelsHidden()
                        .frame(minWidth: 150, maxWidth: .infinity)
                        .disabled(true)
                    }
                    Toggle(model.t("Launch Bimeron with macOS"), isOn: .constant(false))
                        .disabled(true)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppPalette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppPalette.border(colorScheme)))

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(model.t("Bimeron service")).font(.headline)
                        Spacer()
                        Text(model.t("Service: not connected"))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        Button(model.t("Stop")) {}
                        Button(model.t("Check for Core updates")) {}
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                    Text(model.t("Service controls will be available after Core integration."))
                        .foregroundStyle(.secondary)
                    Toggle(model.t("Enable beta Core updates"), isOn: .constant(false))
                        .disabled(true)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppPalette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppPalette.border(colorScheme)))

                HStack {
                    Button { showDiagnosticsExport = true } label: {
                        Text(model.t("Save diagnostics report…"))
                            .foregroundStyle(AppPalette.blue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(AppPalette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AppPalette.border(colorScheme)))
                    }
                    Spacer()
                    Button(action: quit) {
                        Text(model.t("Quit Bimeron"))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(AppPalette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AppPalette.border(colorScheme)))
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 18)
            }
            .frame(maxWidth: 800, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            .padding(.top, 27)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .fileExporter(isPresented: $showDiagnosticsExport,
                      document: LogDocument(text: diagnostics),
                      contentType: .plainText,
                      defaultFilename: "Bimeron-diagnostics") { result in
            if case .failure(let error) = result { model.report(error) }
        }
    }

    private var diagnostics: String {
        let entries = model.log.map { "[\($0.date.formatted(date: .omitted, time: .standard))] \($0.message)" }
        return (["Bimeron diagnostics", "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
                 "Profiles: \(model.profiles.count)", "Core: not connected", "", "Log:"] + entries)
            .joined(separator: "\n")
    }
}
