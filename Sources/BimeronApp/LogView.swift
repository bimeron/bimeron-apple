import SwiftUI

struct LogView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var exportSnapshot: DiagnosticSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.t("Log")).font(.system(size: 24, weight: .bold)).padding(.top, 27)
            Toggle(model.t("Keep previous entries"), isOn: .constant(true)).disabled(true)
            Group {
            if model.log.isEmpty {
                ContentUnavailableView(model.t("No entries yet"), systemImage: "text.alignleft")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(model.log) { entry in
                        Text("[\(entry.displayedTime(locale: Locale(identifier: model.language)))] \(entry.message)")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
            }
            }
            .background(AppPalette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AppPalette.border(colorScheme)))
            HStack {
                Button(model.t("Save log…")) { exportSnapshot = model.diagnosticSnapshot() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(model.log.isEmpty)
                Button(model.t("Clear")) { model.clearLog() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(model.log.isEmpty)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 25)
        .background(AppPalette.canvas(colorScheme))
        .sheet(item: $exportSnapshot) { snapshot in
            DiagnosticExportView(model: model, snapshot: snapshot)
        }
    }
}
