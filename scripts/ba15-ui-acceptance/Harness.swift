import AppKit
import ApplicationServices
import BimeronModel
import SwiftUI

final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    override func integer(forKey key: String) -> Int { values[key] as? Int ?? 0 }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values.removeValue(forKey: key) }
    override func dictionaryRepresentation() -> [String: Any] { values }
    override func synchronize() -> Bool { true }
}

@main struct BA15Harness {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(60))
            print("FAIL: owned harness watchdog exceeded 60 seconds")
            exit(124)
        }
        Task { @MainActor in
            do { try await Driver().run(); exit(0) }
            catch { print("FAIL: \(error)"); exit(1) }
        }
        app.run()
    }
}

@MainActor private final class Driver {
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["BA15_ROOT"]!)
    let appAX = AXUIElementCreateApplication(getpid())
    var window: NSWindow!

    func check(_ condition: Bool, _ message: String) throws {
        print("\(condition ? "PASS" : "FAIL"): \(message)")
        if !condition { throw NSError(domain: message, code: 1) }
    }

    func settle() async { try? await Task.sleep(for: .milliseconds(350)) }

    func onMainThread() -> Bool { Thread.isMainThread }

    func attribute(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(node, key as CFString, &value)
        return value
    }

    func nodes(_ node: AXUIElement) -> [AXUIElement] {
        [node] + ((attribute(node, kAXChildrenAttribute) as? [AXUIElement]) ?? []).flatMap { nodes($0) }
    }

    func label(_ node: AXUIElement) -> [String] {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap { attribute(node, $0) as? String }
    }

    func button(_ title: String) -> AXUIElement? {
        nodes(appAX).first {
            attribute($0, kAXRoleAttribute) as? String == kAXButtonRole && label($0).contains(title)
        }
    }

    func press(_ node: AXUIElement, _ description: String) async throws {
        let status = AXUIElementPerformAction(node, kAXPressAction as CFString)
        print("NATIVE own-process AX action: \(description), status=\(status.rawValue)")
        await settle()
        try check(status == .success, "AX action accepted: \(description)")
    }

    func capture(_ name: String) throws {
        let view = window.contentView!
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: root.appending(path: "evidence/\(name).png"))
        print("CAPTURE: \(name); capture alone is not visual acceptance")
    }

    func dumpTree() throws {
        let text = nodes(appAX).map {
            "\(String(describing: attribute($0, kAXRoleAttribute))) | \(label($0).joined(separator: " | "))"
        }.joined(separator: "\n")
        try text.write(to: root.appending(path: "evidence/own-process-ax.txt"), atomically: false, encoding: .utf8)
    }

    func run() async throws {
        try check(onMainThread() && root.path.hasPrefix("/private/tmp/bimeron-ba15-ui."), "main-thread owned host and scoped root")
        try check(AXIsProcessTrusted(), "existing AX trust; no permission request")
        let defaults = MemoryDefaults()
        defaults.set("en", forKey: "language")
        try check(defaults.string(forKey: "language") == "en" && defaults.string(forKey: "absent") == nil, "memory preferences self-check")
        let library = ProfileLibrary(directory: root.appending(path: "profiles"))
        let model = AppModel(library: library, coreCLI: nil, defaults: defaults, preferredLanguages: ["en"])
        await model.load()
        try check(model.profiles.isEmpty && model.alertMessage == nil, "empty temporary library loaded")
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 720, height: 600), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "BA15 isolated synthetic acceptance"
        window.contentView = NSHostingView(rootView: MainWindow(model: model, quit: {}).environment(\.colorScheme, .light))
        window.appearance = NSAppearance(named: .aqua)
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        await settle()
        print("BOUNDARY: own NSApplication/window only; no Add, keys, panels, clipboard, Core or application entry point")
        try capture("empty-minimum-en-light")
        for page in [Page.settings, .log, .about, .profiles] {
            guard let control = button(model.t(page.title)) else { throw NSError(domain: "Missing sidebar \(page.rawValue)", code: 2) }
            try await press(control, "sidebar \(page.rawValue)")
            try check(model.page == page, "sidebar routes to \(page.rawValue)")
        }
        for index in 1...12 {
            let name = String(format: "BA15 synthetic %02d", index) + " — Long profile name for bounded layout acceptance / Длинное имя синтетического профиля"
            let document = try EditorProtocol.socks5.document(name: name, values: ["Server": "example.invalid", "Port": "1080"])
            try await library.restore(StoredProfile(document: document))
        }
        await model.load()
        await settle()
        try check(model.profiles.count == 12 && model.selectedID == nil, "synthetic fixture setup; not UI creation acceptance")
        try capture("populated-minimum-en-light")
        for size in [NSSize(width: 720, height: 600), NSSize(width: 855, height: 628), NSSize(width: 1100, height: 800)] {
            for language in ["en", "ru"] {
                for dark in [false, true] {
                    // Keep the same owned window and fixtures; only memory state and host presentation change.
                    model.language = language
                    window.contentView = NSHostingView(rootView: MainWindow(model: model, quit: {}).environment(\.colorScheme, dark ? .dark : .light))
                    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    window.setContentSize(size)
                    await settle()
                    try check(window.attachedSheet == nil, "layout capture is unobscured by an editor sheet")
                    try capture("populated-\(Int(size.width))x\(Int(size.height))-\(language)-\(dark ? "dark" : "light")")
                }
            }
        }
        model.language = "en"
        window.contentView = NSHostingView(rootView: MainWindow(model: model, quit: {}).environment(\.colorScheme, .light))
        window.appearance = NSAppearance(named: .aqua)
        window.setContentSize(NSSize(width: 720, height: 600))
        await settle()
        try dumpTree()
        let profile = model.profiles[0]
        let rowLabel = profile.document.name + ", SOCKS5 · System VPN"
        let rowMatches = nodes(appAX).filter {
            attribute($0, kAXRoleAttribute) as? String == kAXButtonRole && label($0).contains(rowLabel)
        }
        if rowMatches.count == 1, let row = rowMatches.first {
            try await press(row, "synthetic profile row")
            try check(model.selectedID == profile.id, "native row selection changes selected profile")
            guard let edit = button(model.t("Edit")) else { throw NSError(domain: "Missing selected Edit button", code: 3) }
            // A sheet can invalidate its AX element; one attempt, then inspect the result.
            let status = AXUIElementPerformAction(edit, kAXPressAction as CFString)
            print("NATIVE own-process AX Edit single attempt: status=\(status.rawValue)")
            await settle()
            try check(window.attachedSheet != nil, "MainWindow Edit presents an owned sheet")
            print("LIMIT: sheet presentation does not establish editor field/save/cancel acceptance")
        } else if rowMatches.isEmpty {
            print("BLOCKED unsupported: exact composite profile row AXButton label absent; selection/Edit not accepted; inspect own-process-ax.txt")
        } else {
            print("BLOCKED ambiguous: \(rowMatches.count) AXButtons match exact composite profile row label; selection/Edit not accepted; inspect own-process-ax.txt")
        }
        print("UNTESTED: visual review of captures, scrolling interaction, focus restoration, physical keyboard, VoiceOver, full app commands/E2E, live runtime")
        print("COMPLETE: bounded supported checks finished; BLOCKED/UNTESTED are not passes")
    }
}
