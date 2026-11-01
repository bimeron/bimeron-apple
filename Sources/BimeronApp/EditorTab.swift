enum EditorTab: String, CaseIterable {
    case general, vless, network, routing, raw
    var title: String {
        switch self {
        case .general: "General"
        case .vless: "VLESS"
        case .network: "Network"
        case .routing: "Routing"
        case .raw: "Raw config"
        }
    }
}
