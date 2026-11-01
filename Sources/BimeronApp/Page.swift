enum Page: String, CaseIterable, Identifiable {
    case profiles, settings, log, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .profiles: "Profiles"
        case .settings: "Settings"
        case .log: "Log"
        case .about: "About"
        }
    }
    var symbol: String {
        switch self {
        case .profiles: "square.stack.3d.up"
        case .settings: "gearshape"
        case .log: "text.alignleft"
        case .about: "info.circle"
        }
    }
}
