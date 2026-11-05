import Foundation
import Testing
@testable import BimeronModel

@Test func routingDisabledFieldEditsPreserveUntouchedSourceBytes() throws {
    let source = "\u{FEFF}[Routing]\r\nDefault = proxy\n  #[Rule]\r\n\t#Domain=\"first.example\"\n  #Action=\"block\"\r\n; original comment\n\r\n  # # nested comment without final newline"
    for field in ["destination", "action"] {
        var document = try ConfigDocument(source)
        #expect(document.formEditingIssue == nil)
        var rule = try #require(document.rules.first)
        let expected: String
        if field == "destination" {
            rule.destination = "changed.example"
            expected = source.replacingOccurrences(of: "\t#Domain=\"first.example\"", with: "# Domain = changed.example")
        } else {
            rule.action = "direct"
            expected = source.replacingOccurrences(of: "  #Action=\"block\"", with: "# Action = direct")
        }
        document.updateRule(rule)
        #expect(Data(document.text.utf8) == Data(expected.utf8))
        let reopened = try ConfigDocument(document.text)
        #expect(reopened.formEditingIssue == nil)
        #expect(reopened.rules == [rule])
    }
}
