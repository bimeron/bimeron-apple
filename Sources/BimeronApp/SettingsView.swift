import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var model: AppModel
    let quit: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var showCoreConsent = false
    @State private var showCorePicker = false
    @State private var exportSnapshot: DiagnosticSnapshot?

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

                // Detailed statistics panel intentionally hidden until its placement is decided (user, 2026-11-05).
                // StatisticsView(snapshot: model.connection.statistics, translate: model.t, locale: Locale(identifier: model.language))

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
                    Toggle(model.t("Enable beta Core updates"), isOn: .constant(false))
                        .disabled(true)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppPalette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppPalette.border(colorScheme)))

                VStack(alignment: .leading, spacing: 12) {
                    Text(model.t("Session Core executable")).font(.headline)
                    Text(model.coreSelectionStatus)
                    Text(model.t("Session only. Metadata is untrusted and does not approve installation or service readiness."))
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(model.t("Select executable…")) { showCoreConsent = true }
                        Button(model.t("Reset to default")) { model.resetCoreExecutable() }
                        if case .probing = model.coreSelection {
                            Button(model.t("Cancel check")) { model.cancelCoreProbe() }
                        }
                    }
                    .disabled(model.validationBusy)
                }

                HStack {
                    Button { exportSnapshot = model.diagnosticSnapshot() } label: {
                        Text(model.t("Save diagnostics report…"))
                            .foregroundStyle(.primary)
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
        .confirmationDialog(model.t("Allow executing the file you select for version, capabilities, and configuration validation?"),
                            isPresented: $showCoreConsent, titleVisibility: .visible) {
            Button(model.t("Choose and allow execution…")) { showCorePicker = true }
        }
        .fileImporter(isPresented: $showCorePicker, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { model.selectCoreExecutable(url) }
        }
        .sheet(item: $exportSnapshot) { snapshot in
            DiagnosticExportView(model: model, snapshot: snapshot)
        }
    }
}
