import BimeronModel
import SwiftUI
import UniformTypeIdentifiers

struct MainWindow: View {
    private static let logo = NSImage(contentsOf: Bundle.module.url(forResource: "blue-64", withExtension: "png")!)!
    @Bindable var model: AppModel
    let quit: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var showAdd = false
    @State private var showImporter = false
    @State private var showError = false
    @State private var editorProfile: StoredProfile?
    @State private var hoveredPage: Page?
    @State private var deleteKeyMonitor: Any?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            Group {
                switch model.page {
                case .profiles:
                    ProfilesView(model: model, add: { showAdd = true }, importFile: { showImporter = true }, edit: { editorProfile = $0 }, remove: confirmDelete)
                case .settings: SettingsView(model: model, quit: quit)
                case .log: LogView(model: model)
                case .about: AboutView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppPalette.canvas(colorScheme))
        .sheet(isPresented: $showAdd) { AddProfileView(model: model) }
        .sheet(item: $editorProfile) { EditorView(model: model, profile: $0) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText, .data]) { result in
            switch result {
            case .success(let url): Task { await model.importFile(url) }
            case .failure(let error): model.report(error)
            }
        }
        .alert(model.t("Error"), isPresented: $showError) {
            Button("OK") { model.alertMessage = nil }
        } message: { Text(model.alertMessage ?? "") }
        .onChange(of: model.alertMessage) { _, value in showError = value != nil }
        .onAppear {
            deleteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                handleProfileKey(event)
            }
        }
        .onDisappear {
            if let deleteKeyMonitor { NSEvent.removeMonitor(deleteKeyMonitor) }
            deleteKeyMonitor = nil
        }
    }

    private func handleProfileKey(_ event: NSEvent) -> NSEvent? {
        guard model.page == .profiles, !model.showDeleteDialog,
              !showAdd, !showImporter, editorProfile == nil,
              NSApp.keyWindow?.attachedSheet == nil else { return event }
        if event.keyCode == 51,
           event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
           model.selected != nil {
            confirmDelete()
            return nil
        }
        if event.keyCode == 6, event.modifierFlags.contains(.command),
           event.modifierFlags.intersection([.option, .control]).isEmpty {
            if event.modifierFlags.contains(.shift) {
                guard model.canRedoDelete else { return event }
                Task { await model.redoDelete() }
            } else {
                guard model.canUndoDelete else { return event }
                Task { await model.undoDelete() }
            }
            return nil
        }
        return event
    }

    private func confirmDelete() {
        guard let profile = model.selected, let window = NSApp.keyWindow,
              !model.showDeleteDialog else { return }
        model.showDeleteDialog = true
        let alert = NSAlert()
        alert.messageText = model.t("Remove profile?")
        alert.informativeText = profile.document.name
        alert.alertStyle = .warning
        let delete = alert.addButton(withTitle: model.t("Remove"))
        delete.bezelColor = .systemRed
        delete.keyEquivalent = "\r"
        let cancel = alert.addButton(withTitle: model.t("Cancel"))
        cancel.keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { response in
            model.showDeleteDialog = false
            if response == .alertFirstButtonReturn {
                Task { await model.delete(profile) }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(nsImage: Self.logo)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
                Text("Bimeron")
                    .font(.system(size: 24, weight: .bold))
                    .frame(height: 24)
            }
                .foregroundStyle(AppPalette.blue)
                .padding(.horizontal, 12)
                .padding(.top, 30)
                .padding(.bottom, 20)
            ForEach(Page.allCases) { page in
                Button {
                    model.page = page
                } label: {
                    Label(model.t(page.title), systemImage: page.symbol)
                        .font(.system(size: 15))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 12)
                        .foregroundStyle(model.page == page ? AppPalette.blue : .primary)
                        .background(model.page == page ? AppPalette.blue.opacity(0.12) :
                                    hoveredPage == page ? AppPalette.blue.opacity(0.06) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { hoveredPage = page }
                    else if hoveredPage == page { hoveredPage = nil }
                }
                .accessibilityAddTraits(model.page == page ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(width: 190)
        .background {
            WindowDragArea()
                .background(AppPalette.sidebar(colorScheme))
        }
    }
}

private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DraggableView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class DraggableView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
