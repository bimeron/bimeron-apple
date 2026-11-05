import SwiftUI

@main struct BimeronApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    private static let menuIcon: NSImage = {
        let image = NSImage(contentsOf: Bundle.module.url(forResource: "menu-disconnected-44", withExtension: "png")!)!
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    var body: some Scene {
        Window(model.t("Bimeron"), id: "main") {
            MainWindow(model: model, quit: { NSApp.terminate(nil) })
                .frame(minWidth: 720, minHeight: 600)
                .task { await model.load() }
                .task { await model.connection.monitor() }
                .onChange(of: model.theme, initial: true) { _, theme in
                    NSApp.appearance = switch theme {
                    case "light": NSAppearance(named: .aqua)
                    case "dark": NSAppearance(named: .darkAqua)
                    default: nil
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 855, height: 628)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(model.t("Settings")) { model.page = .settings }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button(model.t("Profiles")) { model.page = .profiles }
                    .keyboardShortcut("1", modifiers: .command)
                Button(model.t("Settings")) { model.page = .settings }
                    .keyboardShortcut("2", modifiers: .command)
                Button(model.t("Log")) { model.page = .log }
                    .keyboardShortcut("3", modifiers: .command)
                Button(model.t("About")) { model.page = .about }
                    .keyboardShortcut("4", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Image(nsImage: Self.menuIcon)
                .accessibilityLabel(model.t(model.connection.statusKey))
        }
    }
}
