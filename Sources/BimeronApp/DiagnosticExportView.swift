import SwiftUI

struct DiagnosticExportView: View {
    let model: AppModel
    let snapshot: DiagnosticSnapshot
    @Environment(\.dismiss) private var dismiss
    @State private var includeFreeText = false
    @State private var showExporter = false
    @State private var document = LogDocument(text: "")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.t("Review diagnostics export")).font(.title2)
            Text(model.t("Only the preview below will be saved. Nothing is sent over the network."))
            Toggle(model.t("Include raw Core and user text"), isOn: $includeFreeText)
                .disabled(showExporter)
            Text(model.t("Raw text may contain passwords, keys, links, paths, or other sensitive data. Review it before saving; no redaction is performed."))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(snapshot.text(includeFreeText: includeFreeText))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 240)
            HStack {
                Button(model.t("Cancel")) { dismiss() }
                Spacer()
                Button(model.t("Save reviewed snapshot…")) {
                    document = LogDocument(text: snapshot.text(includeFreeText: includeFreeText))
                    showExporter = true
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 660, height: 520)
        .fileExporter(isPresented: $showExporter, document: document,
                      contentType: .plainText, defaultFilename: "Bimeron-diagnostics") { result in
            if case .failure(let error) = result,
               let failure = Self.reportableExportFailure(error) {
                model.report(failure)
            }
        }
    }

    static func reportableExportFailure(_ error: Error) -> CocoaError? {
        let failure = error as NSError
        guard !(error is CancellationError),
              !(failure.domain == NSCocoaErrorDomain && failure.code == NSUserCancelledError) else {
            return nil
        }
        // Export errors must not send destination paths or arbitrary error details into history.
        return CocoaError(.fileWriteUnknown)
    }
}
