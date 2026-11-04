import AppKit
import SwiftUI
import Testing
@testable import BimeronApp

@Test @MainActor func rawEditorTracksDisabledEnvironmentWithoutChangingTextOrSelection() async throws {
    let text = "[Profile]\nName = Draft\n"
    let host = NSHostingView(rootView: ConfigTextEditor(text: .constant(text)).disabled(true))
    host.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
    let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    defer { window.orderOut(nil) }

    func textView(in view: NSView) -> NSTextView? {
        if let editor = view as? NSTextView { return editor }
        return view.subviews.lazy.compactMap { textView(in: $0) }.first
    }
    func settle() async throws {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        host.layoutSubtreeIfNeeded()
    }

    try await settle()
    let editor = try #require(textView(in: host))
    #expect(!editor.isEditable)
    #expect(editor.isSelectable)
    #expect(editor.string == text)
    let selection = NSRange(location: 2, length: 5)
    editor.setSelectedRange(selection)

    for disabled in [false, true, false] {
        host.rootView = ConfigTextEditor(text: .constant(text)).disabled(disabled)
        try await settle()
        #expect(textView(in: host) === editor)
        #expect(editor.isEditable == !disabled)
        #expect(editor.isSelectable)
        #expect(editor.string == text)
        #expect(editor.selectedRange() == selection)
    }
}
