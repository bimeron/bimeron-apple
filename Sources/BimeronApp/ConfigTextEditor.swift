import AppKit
import SwiftUI

struct ConfigTextEditor: NSViewRepresentable {
    @Binding var text: String
    var accessibilityLabel: String = ""

    private static let editorFont = NSFont(name: "Courier New", size: NSFont.systemFontSize)
        ?? NSFont.userFixedPitchFont(ofSize: NSFont.systemFontSize)
        ?? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    private static let boldEditorFont = NSFont(name: "Courier New Bold", size: NSFont.systemFontSize)
        ?? editorFont

    func makeNSView(context: Context) -> NSScrollView {
        let view = NSTextView()
        view.delegate = context.coordinator
        view.setAccessibilityLabel(accessibilityLabel)
        view.isEditable = context.environment.isEnabled
        view.isRichText = false
        view.allowsUndo = true
        view.font = Self.editorFont
        view.textContainerInset = NSSize(width: 8, height: 8)
        view.backgroundColor = .textBackgroundColor
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.string = text
        context.coordinator.highlight(view)

        let scroll = NSScrollView()
        scroll.documentView = view
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        view.isEditable = context.environment.isEnabled
        view.setAccessibilityLabel(accessibilityLabel)
        guard view.string != text else { return }
        let selection = view.selectedRange()
        view.string = text
        view.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        context.coordinator.highlight(view)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ConfigTextEditor

        init(_ parent: ConfigTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            highlight(view)
        }

        @MainActor func highlight(_ view: NSTextView) {
            guard let storage = view.textStorage else { return }
            let source = view.string as NSString
            let whole = NSRange(location: 0, length: source.length)
            storage.beginEditing()
            storage.setAttributes([
                .font: ConfigTextEditor.editorFont,
                .foregroundColor: NSColor.textColor
            ], range: whole)
            source.enumerateSubstrings(in: whole, options: .byLines) { line, range, _, _ in
                guard let line else { return }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                    storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
                } else if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                    storage.addAttributes([
                        .foregroundColor: NSColor.systemTeal,
                        .font: ConfigTextEditor.boldEditorFont
                    ], range: range)
                } else if let equal = line.firstIndex(of: "=") {
                    let keyLength = (line[..<equal] as NSString).length
                    storage.addAttributes([
                        .foregroundColor: NSColor.systemPurple,
                        .font: ConfigTextEditor.boldEditorFont
                    ], range: NSRange(location: range.location, length: keyLength))
                    let value = line[line.index(after: equal)...] as NSString
                    if value.length > 0 {
                        storage.addAttribute(.foregroundColor, value: NSColor.systemBlue,
                                             range: NSRange(location: range.location + keyLength + 1, length: value.length))
                    }
                }
            }
            storage.endEditing()
        }
    }
}
