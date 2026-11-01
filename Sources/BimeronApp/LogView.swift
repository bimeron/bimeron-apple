import SwiftUI

struct LogView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showExport = false

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
                        Text("[\(entry.date.formatted(date: .omitted, time: .standard))] \(entry.message)")
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
                Button(model.t("Save log…")) { showExport = true }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(model.log.isEmpty)
                Button(model.t("Clear")) { model.log.removeAll() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(model.log.isEmpty)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 25)
        .background(AppPalette.canvas(colorScheme))
        .fileExporter(isPresented: $showExport,
                      document: LogDocument(text: model.log.map { "[\($0.date.formatted(date: .omitted, time: .standard))] \($0.message)" }.joined(separator: "\n")),
                      contentType: .plainText, defaultFilename: "Bimeron-log") { result in
            if case .failure(let error) = result { model.report(error) }
        }
    }
}
