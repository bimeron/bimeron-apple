import AppKit
import ApplicationServices
import BimeronModel
import BimeronCoreCLI

// Only controls belonging to the current synthetic editor sheet are inspected or changed.
@MainActor extension Driver {
    func nativeViews(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { nativeViews($0) }
    }

    func inspectEditorControls() {
        dumpTree()
        for view in nativeViews(sheet.contentView!) {
            if let field = view as? NSTextField, field.isEditable {
                print("CONTROL: \(type(of: field)) placeholder=\(field.placeholderString ?? "") label=\(field.accessibilityLabel() ?? "") secure=\(field is NSSecureTextField)")
            } else if let control = view as? NSControl {
                print("CONTROL: \(type(of: control)) label=\(control.accessibilityLabel() ?? "")")
            }
        }
    }

    func editField(_ title: String, value: String, model: AppModel, secret: Bool = false) async throws {
        let localized = model.t(title)
        let sheets = nodes(appAX).filter { (attribute($0, kAXRoleAttribute) as? String) == kAXSheetRole }
        guard sheets.count == 1, let ownedSheet = sheets.first else {
            throw NSError(domain: "Ambiguous own-process editor sheet", code: 20)
        }
        let tree = nodes(ownedSheet)
        func isTitle(_ node: AXUIElement) -> Bool {
            [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].contains {
                (attribute(node, $0) as? String) == localized
            }
        }
        let candidates = tree.enumerated().filter { index, node in
            guard (attribute(node, kAXRoleAttribute) as? String) == kAXTextFieldRole else { return false }
            if let title = attribute(node, kAXTitleUIElementAttribute), CFGetTypeID(title) == AXUIElementGetTypeID(),
               isTitle(unsafeBitCast(title, to: AXUIElement.self)) { return true }
            // SwiftUI exposes some form labels as the immediately preceding AX sibling.
            guard index > 0, isTitle(tree[index - 1]),
                  (attribute(tree[index - 1], kAXRoleAttribute) as? String) == kAXStaticTextRole,
                  let parent = attribute(node, kAXParentAttribute),
                  let titleParent = attribute(tree[index - 1], kAXParentAttribute) else { return false }
            return CFEqual(parent, titleParent)
        }.map { $0.element }
        guard candidates.count == 1, let target = candidates.first,
              let position = attribute(target, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(target, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID(),
              let screenTop = NSScreen.screens.first?.frame.maxY else {
            inspectEditorControls()
            throw NSError(domain: "Unsupported own-sheet AX field: \(title), matches=\(candidates.count)", code: 20)
        }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions) else {
            throw NSError(domain: "Missing own-sheet field geometry: \(title)", code: 20)
        }
        let frame = NSRect(x: point.x, y: screenTop - point.y - dimensions.height,
                           width: dimensions.width, height: dimensions.height)
        print("GEOMETRY: \(title) AX point=\(point) size=\(dimensions) converted=\(frame) sheet=\(sheet.frame) screenTop=\(screenTop)")
        let matches = nativeViews(sheet.contentView!).compactMap { $0 as? NSTextField }.filter { field in
            guard field.isEditable, field.window === sheet else { return false }
            let native = sheet.convertToScreen(field.convert(field.bounds, to: nil))
            print("GEOMETRY: native \(type(of: field)) bounds=\(field.bounds) screen=\(native) delta=\(native.minX - frame.minX),\(native.minY - frame.minY),\(native.width - frame.width),\(native.height - frame.height)")
            return abs(native.minX - frame.minX) <= 2 && abs(native.minY - frame.minY) <= 2
                && abs(native.width - frame.width) <= 2 && abs(native.height - frame.height) <= 2
        }
        guard matches.count == 1, let field = matches.first else {
            inspectEditorControls()
            throw NSError(domain: "Unsupported native field mapping: \(title), matches=\(matches.count)", code: 20)
        }
        try check(!secret || field is NSSecureTextField, "\(title) uses native secure control")
        field.scrollToVisible(field.bounds)
        try check(sheet.makeFirstResponder(field), "\(title) accepts native focus")
        guard let editor = sheet.fieldEditor(true, for: field) as? NSTextView else {
            throw NSError(domain: "Missing own-window field editor: \(title)", code: 21)
        }
        editor.selectAll(nil)
        editor.insertText(value, replacementRange: editor.selectedRange())
        // Commit through AppKit editing notifications, without touching SwiftUI bindings.
        sheet.makeFirstResponder(nil)
        await settle()
        try check(field.stringValue == value, "\(title) accepts changed text")
    }

    func selectProtocol(_ variant: EditorProtocol) async throws {
        let pickers = nodes(appAX).filter { (attribute($0, kAXRoleAttribute) as? String) == kAXPopUpButtonRole }
        guard let picker = pickers.first(where: { node in
            EditorProtocol.allCases.contains { label(node).split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.contains($0.rawValue) }
        }) else {
            inspectEditorControls()
            throw NSError(domain: "Unsupported creation protocol picker", code: 22)
        }
        try check(AXUIElementPerformAction(picker, kAXPressAction as CFString) == .success, "open own protocol picker")
        await settle()
        guard let item = nodes(appAX).first(where: {
            (attribute($0, kAXRoleAttribute) as? String) == kAXMenuItemRole && label($0).split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.contains(variant.rawValue)
        }) else { throw NSError(domain: "Missing protocol menu item \(variant.rawValue)", code: 23) }
        try check(AXUIElementPerformAction(item, kAXPressAction as CFString) == .success, "select \(variant.rawValue)")
        await settle()
    }

    func rawDocument(_ model: AppModel) async throws -> ConfigDocument {
        try await press(model.t("Raw config"))
        guard let editor = textViews(sheet.contentView!).first else {
            throw NSError(domain: "Missing native Raw editor", code: 24)
        }
        return try ConfigDocument(editor.string)
    }

    func assertEndpoint(_ document: ConfigDocument, variant: EditorProtocol, host: String) throws {
        if variant == .vmess {
            let encoded = String(document.accessKey.dropFirst("vmess://".count))
            let data = Data(base64Encoded: encoded) ?? Data()
            let json = try JSONSerialization.jsonObject(with: data) as? [String: String]
            try check(json?["add"] == host && json?["port"] == "8443", "VMess native edits reach encoded endpoint")
        } else if variant.generated {
            let url = URLComponents(string: document.accessKey)
            try check(url?.host == host && url?.port == 8443, "\(variant.rawValue) native edits reach generated endpoint")
        } else {
            try check(document.value("AccessKey", "Server") == host && document.value("AccessKey", "Port") == "8443", "\(variant.rawValue) native edits reach explicit endpoint")
        }
    }

    func runEditor() async throws {
        try check(onMainThread() && root.path.hasPrefix("/private/tmp/bimeron-isolated-ui."), "editor mode uses main thread and scoped temporary root")
        let defaults = MemoryDefaults()
        defaults.set("en", forKey: "language")
        let library = ProfileLibrary(directory: root.appending(path: "editor-profiles"))
        let model = AppModel(library: library, coreCLI: CoreCLI(executableURL: root.appending(path: "mock-validate")), defaults: defaults, preferredLanguages: ["en"])
        let profile = StoredProfile(document: try EditorProtocol.ss.document(name: "Synthetic editor", values: ["Server": "original.invalid", "Port": "443", "Method": "aes-256-gcm", "Password": "synthetic-only"]))
        try check(AXIsProcessTrusted(), "existing AX trust only; no permission request")
        AXUIElementSetAttributeValue(appAX, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        print("ISOLATION: editor-only; temporary library, MemoryDefaults, mock validator, sandbox; no AddProfileView")
        await open(model, profile, creating: true)
        inspectEditorControls()
        for (index, variant) in EditorProtocol.allCases.enumerated() {
            if variant != .ss { try await selectProtocol(variant) }
            let host = "editor-\(index).invalid"
            try await editField("Server", value: host, model: model)
            try await editField("Port", value: "8443", model: model)
            if variant == .ss || variant == .socks5 || variant == .trojan || (variant.generated && variant.fields.contains("Password")) {
                try await editField("Password", value: "synthetic-secret-\(index)", model: model, secret: true)
            }
            if variant == .tuic || variant == .vmess {
                try await editField(ProtocolField.generated("ID").title, value: "123e4567-e89b-12d3-a456-426614174000", model: model, secret: true)
            }
            let document = try await rawDocument(model)
            try assertEndpoint(document, variant: variant, host: host)
            try capture("editor-fields-\(index)")
            try await press("Protocol")
        }
        // Revisit every protocol after editing all others: acceptance checks draft isolation.
        for (index, variant) in EditorProtocol.allCases.enumerated() {
            try await selectProtocol(variant)
            let document = try await rawDocument(model)
            try assertEndpoint(document, variant: variant, host: "editor-\(index).invalid")
            try await press("Protocol")
        }
        try await selectProtocol(.anytls)
        let generated = try await rawDocument(model)
        guard let generatedHost = URLComponents(string: generated.accessKey)?.host else {
            throw NSError(domain: "Missing generated Raw authority host", code: 25)
        }
        try check(generated.text.contains(generatedHost), "Raw authority fixture contains generated host")
        let raw = textViews(sheet.contentView!).first!
        sheet.makeFirstResponder(raw)
        raw.selectAll(nil)
        raw.insertText(generated.text.replacingOccurrences(of: generatedHost, with: "raw-authority.invalid"), replacementRange: raw.selectedRange())
        await settle()
        try await press("Protocol")
        try check(hasText("Keep edited generated links in Raw"), "Raw authority blocks stale generated form")
        try await press("Restore generated access key")
        try check(textViews(sheet.contentView!).first?.string == generated.text, "Restore recovers exact generated draft bytes")
        try await press("Save")
        await waitForDismissal()
        try check(window.attachedSheet == nil, "mock validated generated save dismisses")
        let saved = try await library.load().profiles
        try check(saved.count == 1 && saved[0].document.text == generated.text, "save persists actual edited draft exactly once")
        for language in ["en", "ru"] {
            model.language = language
            for dark in [false, true] {
                await open(model, saved[0], dark: dark)
                try await editField("Name", value: "Unsaved \(language) \(dark)", model: model)
                try await press(model.t("Protocol"))
                try check(nativeViews(sheet.contentView!).contains { $0 is NSSecureTextField }, "imported generated link masked \(language) dark=\(dark)")
                try await toggle(model.t("Show access key"))
                try check(!nativeViews(sheet.contentView!).contains { $0 is NSSecureTextField }, "reveal replaces secure link control")
                try Data().write(to: root.appending(path: "reject"))
                try await press(model.t("Save"))
                try check(window.attachedSheet != nil && hasText(model.t("Core rejected the configuration")), "localized mock rejection retains editor \(language) dark=\(dark)")
                try capture("editor-error-\(language)-\(dark)")
                try FileManager.default.removeItem(at: root.appending(path: "reject"))
                sheet.makeFirstResponder(nil)
                let before = sheet.firstResponder
                await key("\t", code: 48)
                try check(sheet.firstResponder !== before, "own-window Tab advances focus")
                try await press(model.t("Cancel"))
                if hasText(model.t("Keep editing")) {
                    try await press(model.t("Keep editing"))
                    try check(window.attachedSheet != nil, "Keep editing retains sheet")
                    try await press(model.t("Cancel"))
                    try await press(model.t("Discard changes"))
                    await waitForDismissal()
                    try check(window.attachedSheet == nil, "discard dismisses dirty editor")
                } else {
                    print("UNSUPPORTED: dirty confirmation is opaque to own-process AX; no cancel acceptance claimed")
                    if window.attachedSheet != nil { window.endSheet(sheet) }
                }
                let after = try await library.load().profiles
                try check(after.count == 1 && after[0].document.text == generated.text, "rejection/cancel preserve stored bytes")
            }
        }
        print("UNSUPPORTED: Return/Escape shortcuts, picker field acceptance, routing table and visual quality require separate coordinated execution; no pass inferred")
        print("COMPLETE: editor-only native interaction assertions; mock validation only, no real Core/network compatibility claim")
    }
}
