import AppKit
import SwiftUI
import Testing
@testable import BimeronApp

@Test @MainActor func rawEditorTabCommandsMoveFocusWithoutEditingConfiguration() throws {
    let original = "[Profile]\nName = Draft\n"
    var text = original
    let coordinator = ConfigTextEditor(text: Binding(get: { text }, set: { text = $0 })).makeCoordinator()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                          styleMask: [.titled], backing: .buffered, defer: false)
    defer { window.orderOut(nil) }
    let content = try #require(window.contentView)
    let previous = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
    let editor = NSTextView(frame: NSRect(x: 0, y: 50, width: 100, height: 40))
    let next = NSTextView(frame: NSRect(x: 0, y: 100, width: 100, height: 40))
    for view in [previous, editor, next] { content.addSubview(view) }
    previous.nextKeyView = editor
    editor.nextKeyView = next
    next.nextKeyView = previous
    editor.delegate = coordinator
    editor.string = original
    let selection = NSRange(location: 2, length: 5)
    editor.setSelectedRange(selection)

    #expect(window.makeFirstResponder(editor))
    editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
    #expect(window.firstResponder === next)
    #expect(window.makeFirstResponder(editor))
    editor.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
    #expect(window.firstResponder === previous)
    #expect(editor.string == original)
    #expect(editor.selectedRange() == selection)
    #expect(text == original)

    #expect(window.makeFirstResponder(editor))
    editor.setSelectedRange(NSRange(location: 0, length: 0))
    editor.doCommand(by: #selector(NSResponder.insertTabIgnoringFieldEditor(_:)))
    #expect(window.firstResponder === editor)
    #expect(editor.string == "\t" + original)
    #expect(text == editor.string)

    editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    #expect(editor.string == "\t\n" + original)
    #expect(text == editor.string)
}

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
