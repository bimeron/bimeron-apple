import SwiftUI
import UniformTypeIdentifiers

struct LogDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    let text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        try self.init(file: configuration.file)
    }
    init(file: FileWrapper) throws {
        guard file.isRegularFile,
              let data = file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
