import SwiftUI

struct AboutView: View {
    @Bindable var model: AppModel
    private let coreIdentity = (try? BundledCoreManifest.load())?.displayIdentity

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.t("About")).font(.system(size: 24, weight: .bold))
            Text("Bimeron for macOS 0.1.0")
            Text(coreIdentity ?? model.t("Bundled Core information unavailable"))
            Text(model.t(model.connection.runningStatusKey))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
        .padding(.top, 27)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
