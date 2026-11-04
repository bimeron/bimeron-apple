import AppKit
import ApplicationServices
import SwiftUI
import BimeronModel
import BimeronCoreCLI

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

@MainActor @Observable final class SheetState { var shown = false }
struct HarnessHost: View {
    @Bindable var state: SheetState
    let model: AppModel
    let profile: StoredProfile
    let creating: Bool
    var body: some View {
        Text("Isolated EditorView harness — synthetic data only").padding(40)
            .sheet(isPresented: $state.shown) { EditorView(model: model, profile: profile, creating: creating) }
    }
}

struct AuditHost: View {
    @Bindable var state: SheetState
    let content: AnyView
    var body: some View {
        Text("Integrated UI audit — synthetic data only").padding(40)
            .sheet(isPresented: $state.shown) { content }
    }
}

@main struct Harness {
    @MainActor static func main() {
        precondition(Thread.isMainThread)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(150))
            print("FAIL: harness watchdog exceeded 150 seconds")
            exit(124)
        }
        Task { @MainActor in
            do { try await Driver().run(); exit(0) }
            catch { print("FAIL: \(error)"); exit(1) }
        }
        app.run()
    }
}

@MainActor final class Driver {
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HARNESS_ROOT"]!)
    var window: NSWindow!
    var state = SheetState()
    var sheet: NSWindow { window.attachedSheet! }
    func check(_ condition: Bool, _ message: String) throws {
        print("\(condition ? "PASS" : "FAIL"): \(message)")
        if !condition { throw NSError(domain: message, code: 1) }
    }
    func waitForDismissal() async {
        for _ in 0..<40 {
            if window.attachedSheet == nil { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
    func onMainThread() -> Bool { Thread.isMainThread }
    func settle() async { try? await Task.sleep(for: .milliseconds(350)) }
    let appAX = AXUIElementCreateApplication(getpid())
    func attribute(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(node, key as CFString, &value)
        return value
    }
    func nodes(_ node: AXUIElement) -> [AXUIElement] {
        [node] + ((attribute(node, kAXChildrenAttribute) as? [AXUIElement]) ?? []).flatMap { nodes($0) }
    }
    func label(_ n: AXUIElement) -> String {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap { attribute(n, $0) as? String }.joined(separator: " | ")
    }
    func hasText(_ fragment: String) -> Bool { nodes(appAX).contains { label($0).contains(fragment) } }
    func press(_ title: String) async throws {
        guard let button = nodes(appAX).first(where: { (attribute($0, kAXRoleAttribute) as? String) == kAXButtonRole && label($0).split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.contains(title) }) else {
            dumpTree(); throw NSError(domain: "Missing button \(title)", code: 2)
        }
        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        print("ACTION own-process AX press \(title): result=\(result.rawValue)")
        await settle()
        if ["Save", "Cancel", "Keep editing", "Discard changes"].contains(title) {
            // AX can invalidate its element while a sheet changes. Never repeat a mutation.
            print("OBSERVED: single mutation attempt; subsequent state/storage assertions determine outcome")
        } else {
            try check(result == .success, "navigation AX press \(title)")
        }
    }
    func dumpTree() {
        for n in nodes(appAX) { print("AX \(String(describing: attribute(n, kAXRoleAttribute))) | \(label(n))") }
    }
    func textViews(_ view: NSView) -> [NSTextView] {
        (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap { textViews($0) }
    }
    func capture(_ name: String) throws {
        let view = sheet.contentView!
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: root.appending(path: "evidence/\(name).png"))
    }
    func key(_ chars: String, code: UInt16) async {
        let target = sheet
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: target.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        target.sendEvent(event)
        print("EVENT own sheet keyCode=\(code), responder=\(String(describing: target.firstResponder))")
        await settle()
    }
    func open(_ model: AppModel, _ profile: StoredProfile, creating: Bool = false, dark: Bool = false) async {
        if window != nil { window.orderOut(nil) }
        state = SheetState()
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 660), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Isolated synthetic EditorView harness"
        window.contentView = NSHostingView(rootView: HarnessHost(state: state, model: model, profile: profile, creating: creating).environment(\.colorScheme, dark ? .dark : .light))
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.makeKeyAndOrderFront(nil)
        state.shown = true
        await settle()
    }
    func openAudit(_ content: AnyView) async {
        window.orderOut(nil)
        state = SheetState()
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 820, height: 680), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: AuditHost(state: state, content: content))
        window.makeKeyAndOrderFront(nil)
        state.shown = true
        await settle()
    }
    func toggle(_ title: String) async throws {
        guard let node = nodes(appAX).first(where: {
            (attribute($0, kAXRoleAttribute) as? String) == kAXCheckBoxRole && label($0).contains(title)
        }) else { dumpTree(); throw NSError(domain: "Missing toggle", code: 4) }
        let result = AXUIElementPerformAction(node, kAXPressAction as CFString)
        print("ACTION own-process toggle: \(result.rawValue)")
        await settle()
        try check(result == .success, "diagnostics consent AX action")
    }
    func run() async throws {
        try check(onMainThread(), "NSApplication event loop and driver on main thread")
        try check(root.path.hasPrefix("/private/tmp/bimeron-isolated-ui."), "explicit scoped temporary root")
        let defaults = MemoryDefaults()
        defaults.set("en", forKey: "language")
        try check(defaults.string(forKey: "language") == "en" && defaults.string(forKey: "absent") == nil, "in-memory preference reads/writes")
        let library = ProfileLibrary(directory: root.appending(path: "profiles"))
        let profile = StoredProfile(document: try EditorProtocol.socks5.document(name: "Synthetic original", values: ["Server": "example.invalid", "Port": "1080"]))
        let offline = AppModel(library: library, coreCLI: nil, defaults: defaults, preferredLanguages: ["en"])
        print("ISOLATION VERIFIED BEFORE WINDOW: explicit library, memory defaults, nil Core, sandbox preflight; no AddProfileView, panels, daemon or clipboard")
        try check(AXIsProcessTrusted(), "existing AX trust; no permission request")
        AXUIElementSetAttributeValue(appAX, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        await open(offline, profile)
        try capture("general-offline")
        sheet.makeFirstResponder(nil)
        let initialResponder = sheet.firstResponder
        await key("\t", code: 48)
        try check(sheet.firstResponder !== initialResponder, "Tab changes first responder")
        await key("\r", code: 36)
        print("OBSERVED Return visible offline error: \(hasText("Core validation is unavailable")); retained editor: \(window.attachedSheet != nil)")
        try await press("Save")
        dumpTree()
        try check(hasText("Core validation is unavailable"), "visible offline validation error")
        try capture("offline-save-error")
        try await press("Raw config")
        let text = textViews(sheet.contentView!).first
        try check(text != nil, "Raw tab exposes native NSTextView")
        if let text {
            sheet.makeFirstResponder(text)
            text.selectAll(nil)
            text.insertText("invalid raw syntax", replacementRange: text.selectedRange())
        }
        await settle()
        try await press("Save")
        try check(hasText("Syntax error") || hasText("Invalid"), "visible Raw parse/validation error")
        try capture("raw-syntax-error")
        try await press("General")
        try check(hasText("Raw profile text"), "invalid Raw blocks switch to General")
        await key("\u{1b}", code: 53)
        dumpTree()
        if window.attachedSheet != nil {
            try capture("escape-result")
            window.endSheet(sheet)
        } else { print("OBSERVED: Escape leaves no attached editor sheet; discard confirmation not established") }
        let mock = CoreCLI(executableURL: root.appending(path: "mock-validate"))
        let model = AppModel(library: library, coreCLI: mock, defaults: defaults, preferredLanguages: ["en"])
        await open(model, profile, creating: true)
        try capture("create")
        try await press("Save")
        await waitForDismissal()
        if window.attachedSheet != nil { dumpTree() }
        try check(window.attachedSheet == nil, "mock validation success dismisses create sheet")
        let saved = try await library.load().profiles
        try check(saved.count == 1, "create persists exactly one synthetic profile")
        await open(model, saved[0])
        try await press("Raw config")
        guard let rawEditor = textViews(sheet.contentView!).first else { throw NSError(domain: "Missing raw editor", code: 3) }
        sheet.makeFirstResponder(rawEditor)
        rawEditor.selectAll(nil)
        rawEditor.insertText(saved[0].document.text.replacingOccurrences(of: "Synthetic original", with: "Synthetic updated"), replacementRange: rawEditor.selectedRange())
        await settle()
        try await press("Save")
        await waitForDismissal()
        try check(window.attachedSheet == nil, "mock validated edit dismisses sheet")
        let updated = try await library.load().profiles
        try check(updated.count == 1 && updated[0].document.name == "Synthetic updated", "Raw edit save persists changed name without duplicate")
        try Data().write(to: root.appending(path: "reject"))
        await open(model, updated[0])
        try await press("Save")
        try check(window.attachedSheet != nil, "mock rejection retains sheet")
        try check(hasText("Core rejected the configuration"), "visible mock rejection error")
        try capture("mock-rejection")
        dumpTree()
        try await press("Cancel")
        try check(window.attachedSheet == nil, "unchanged Cancel dismisses sheet")
        let finalCount = try await library.load().profiles.count
        try check(finalCount == 1, "rejection and cancel preserve stored profile count")
        let finalProfiles = try await library.load().profiles
        try check(finalProfiles[0].document.text == updated[0].document.text, "rejection and cancel preserve stored content")
        try FileManager.default.removeItem(at: root.appending(path: "reject"))
        await open(model, updated[0])
        try await press("Raw config")
        let cancelEditor = textViews(sheet.contentView!).first!
        sheet.makeFirstResponder(cancelEditor)
        cancelEditor.selectAll(nil)
        cancelEditor.insertText(updated[0].document.text + "\n# synthetic unsaved change\n", replacementRange: cancelEditor.selectedRange())
        await settle()
        try await press("Cancel")
        dumpTree()
        if hasText("Keep editing") {
            try await press("Keep editing")
            try check(window.attachedSheet != nil && !hasText("Keep editing") && hasText("synthetic unsaved change"), "Keep editing retains dirty Raw editor and dismisses confirmation")
            try await press("Cancel")
            try await press("Discard changes")
            await waitForDismissal()
            try check(window.attachedSheet == nil, "Discard changes dismisses dirty editor")
        } else {
            print("UNSUPPORTED: edited Cancel exposes no Keep editing action in own-process AX tree; no discard confirmation pass claimed")
        }
        let afterCancel = try await library.load().profiles
        try check(afterCancel[0].document.text == updated[0].document.text, "edited Cancel leaves stored bytes unchanged")
        let values = ["Server": "example.invalid", "Port": "443", "Password": "synthetic-password", "Username": "synthetic-user", "ID": "123e4567-e89b-12d3-a456-426614174000", "Method": "aes-256-gcm"]
        for language in (ProcessInfo.processInfo.environment["HARNESS_SKIP_MATRIX"] == "1" ? [] : ["en", "ru"]) {
            model.language = language
            for dark in [false, true] {
                for variant in EditorProtocol.allCases {
                    let document = try variant.document(name: "Synthetic " + variant.rawValue, values: values)
                    await open(model, StoredProfile(document: document), dark: dark)
                    try await press(model.t("Protocol"))
                    try check(hasText(document.protocolName), "initial protocol tab \(variant.rawValue) \(language) dark=\(dark)")
                    try capture("matrix-\(variant.rawValue.replacingOccurrences(of: " ", with: "-"))-\(language)-\(dark ? "dark" : "light")")
                    window.endSheet(sheet)
                }
            }
        }
        model.language = "en"
        await open(model, profile, creating: true)
        guard let picker = nodes(appAX).first(where: { (attribute($0, kAXRoleAttribute) as? String) == kAXPopUpButtonRole && label($0).contains("Protocol") }) else {
            dumpTree(); throw NSError(domain: "Missing creation protocol picker", code: 5)
        }
        try check(AXUIElementPerformAction(picker, kAXPressAction as CFString) == .success, "open own creation protocol picker")
        await settle()
        guard let item = nodes(appAX).first(where: { (attribute($0, kAXRoleAttribute) as? String) == kAXMenuItemRole && label($0) == "AnyTLS" }) else {
            dumpTree(); throw NSError(domain: "Missing AnyTLS menu item", code: 6)
        }
        try check(AXUIElementPerformAction(item, kAXPressAction as CFString) == .success, "select generated AnyTLS creation draft")
        await settle()
        try await press("Raw config")
        try check(hasText("Restore generated access key"), "generated draft exposes explicit restore action")
        let generatedRaw = textViews(sheet.contentView!).first!
        let baseline = generatedRaw.string
        let custom = try EditorProtocol.anytls.document(name: "Raw authority", values: ["Server": "example.invalid", "Port": "443", "Password": "synthetic"])
        sheet.makeFirstResponder(generatedRaw)
        generatedRaw.selectAll(nil)
        generatedRaw.insertText(custom.text, replacementRange: generatedRaw.selectedRange())
        await settle()
        try await press("Protocol")
        try check(hasText("Keep edited generated links in Raw") && hasText("Raw profile text"), "edited generated Raw blocks stale parameter form")
        try capture("generated-raw-authority")
        try await press("Restore generated access key")
        try check(textViews(sheet.contentView!).first!.string.contains("Name = Raw authority") && !textViews(sheet.contentView!).first!.string.contains("example.invalid"), "restore replaces generated source while preserving Raw profile name")
        print("OBSERVED generated baseline bytes: \(baseline.utf8.count)")
        try await press("Protocol")
        try check(!hasText("Raw profile text"), "restored generated source allows parameter form")
        try await press("Cancel")
        try await press("Discard changes")
        await waitForDismissal()
        try check(window.attachedSheet == nil, "generated draft discard dismisses")
        await model.load()
        var editedID: UUID?
        await openAudit(AnyView(ProfilesView(model: model, add: {}, edit: { editedID = $0.id }, remove: {})))
        if nodes(appAX).contains(where: { label($0).contains("Synthetic updated") }) {
            try await press("Synthetic updated")
            try check(model.selectedID == updated[0].id, "K row selection uses persisted H edited profile")
            try await press("Edit")
            try check(editedID == updated[0].id, "K Edit callback receives selected persisted profile")
        } else {
            dumpTree()
            print("BLOCKED K: own-process AX exposes opaque lazy profile list without row controls; no selection or focus acceptance claimed")
        }
        try capture("integrated-profile-selection")
        window.endSheet(sheet)
        model.record("SYNTHETIC-RAW-SECRET")
        let snapshot = model.diagnosticSnapshot()
        let frozen = snapshot.text(includeFreeText: true)
        try check(snapshot.entries.contains { $0.event?.kind == .validation }, "J snapshot contains H edit validation hooks")
        await openAudit(AnyView(DiagnosticExportView(model: model, snapshot: snapshot)))
        try check(hasText("Free text: excluded") && !hasText("SYNTHETIC-RAW-SECRET"), "J raw text excluded by default in actual preview")
        try capture("diagnostics-default-consent")
        try await toggle("Include raw Core and user text")
        try check(hasText("Free text: included") && hasText("SYNTHETIC-RAW-SECRET"), "J opt-in reveals synthetic raw text in actual preview")
        model.record("LATE-SYNTHETIC-EVENT")
        model.clearLog()
        await settle()
        try check(!hasText("LATE-SYNTHETIC-EVENT") && hasText("SYNTHETIC-RAW-SECRET") && snapshot.text(includeFreeText: true) == frozen, "J preview remains frozen after append and clear")
        try capture("diagnostics-opt-in-frozen")
        try await toggle("Include raw Core and user text")
        try check(!hasText("SYNTHETIC-RAW-SECRET"), "J consent can be revoked before export")
        try await press("Cancel")
        try check(window.attachedSheet == nil, "J cancel dismisses without opening file exporter")
        await openAudit(AnyView(DiagnosticExportView(model: model, snapshot: snapshot)))
        try check(hasText("Free text: excluded") && !hasText("SYNTHETIC-RAW-SECRET"), "J reopened sheet resets consent")
        try await press("Cancel")
        print("COMPLETE: mock validator only; no real Core compatibility claim")
    }
}
