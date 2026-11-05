import BimeronModel
import Foundation
import Testing

@Test(arguments: EditorProtocol.allCases)
func protocolDraftSwitchingPreservesEveryVariantBytes(_ variant: EditorProtocol) throws {
    var drafts = ProtocolDrafts()
    var current = try drafts.select(variant, current: EditorProtocol.ss.document(name: "Draft", values: [:]))
    let values = ["Server": "draft.example", "Port": "9443", "Password": "private:@/?# %value",
                  "Username": "draft-user", "ID": "123e4567-e89b-12d3-a456-426614174000"]
    if variant.generated {
        for key in variant.fields {
            if let value = values[key] { current = try drafts.set(key, value: value, name: "Draft") }
        }
    } else {
        for (key, value) in values { current.set("AccessKey", key, value) }
    }
    let source = "\u{FEFF}" + current.text
        .replacingOccurrences(of: "[AccessKey]\n", with: "[AccessKey]\n; retain protocol extensions\nFuture = opaque%2fvalue\n")
        .replacingOccurrences(of: "\n", with: "\r\n") + "# mixed ending\n# no final newline"
    current = try ConfigDocument(source)
    let bytes = Data(source.utf8)

    for other in EditorProtocol.allCases where other != variant {
        let inactive = try drafts.select(other, current: current)
        current = try drafts.select(variant, current: inactive)
        #expect(Data(current.text.utf8) == bytes)
        #expect(drafts.selected == variant)
        if variant.generated {
            for key in variant.fields {
                if let value = values[key] { #expect(drafts.value(key) == value) }
            }
            try drafts.checkParameterSource(current)
        }
    }
}

@Test(arguments: EditorProtocol.allCases.filter(\.generated))
func everyGeneratedDraftKeepsChangedRawLinkAuthoritative(_ variant: EditorProtocol) throws {
    var drafts = ProtocolDrafts()
    _ = try drafts.select(variant, current: EditorProtocol.ss.document(name: "Draft", values: [:]))
    let generated = try drafts.set("Server", value: "form.example", name: "Draft")
    let rawLink = try variant.uri(values: ["Server": "raw.example", "Password": "raw-secret"])
    let source = "\u{FEFF}" + generated.text.replacingOccurrences(of: "\n", with: "\r\n")
        .replacingOccurrences(of: generated.accessKey, with: rawLink) + "# retained EOF"
    let raw = try ConfigDocument(source)

    try drafts.checkSave(raw, raw: true)
    #expect(throws: ProfileError.invalid("GeneratedAccessKey")) { try drafts.checkSave(raw, raw: false) }
    #expect(throws: ProfileError.invalid("GeneratedAccessKey")) { try drafts.select(.ss, current: raw) }
    #expect(drafts.selected == variant)
    #expect(drafts.value("Server") == "form.example")
    #expect(Data(raw.text.utf8) == Data(source.utf8))

    let restored = try drafts.restoringGeneratedSource(in: raw)
    #expect(Data(restored.text.utf8) == Data(source.replacingOccurrences(of: rawLink, with: generated.accessKey).utf8))
    try drafts.checkSave(restored, raw: false)
}
