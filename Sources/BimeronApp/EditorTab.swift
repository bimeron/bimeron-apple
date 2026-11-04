enum EditorTab: String, CaseIterable {
    case general, upstream, network, routing, raw
    var title: String {
        switch self {
        case .general: "General"
        case .upstream: "Protocol"
        case .network: "Network"
        case .routing: "Routing"
        case .raw: "Raw config"
        }
    }
}
