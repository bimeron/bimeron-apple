import SwiftUI

struct MenuBarContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.t(model.connection.statusKey))
        Divider()
        ForEach(model.profiles) { profile in
            Text(profile.document.name)
        }
        if model.profiles.isEmpty { Text(model.t("No profiles yet")) }
        Divider()
        Button(model.t("Open Bimeron")) {
            openWindow(id: "main")
            NSApp.activate()
        }
        Button(model.t("Quit Bimeron")) { NSApp.terminate(nil) }
    }
}
