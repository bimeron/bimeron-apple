import Foundation
import Darwin

public actor ProfileLibrary {
    public struct Snapshot: Sendable {
        public let profiles: [StoredProfile]
        public let unreadableCount: Int
    }

    private let directory: URL
    private var orderFile: URL { directory.appending(path: "order.json") }

    public init(directory: URL) { self.directory = directory }

    public static func defaultDirectory() -> URL {
        URL.applicationSupportDirectory.appending(path: "Bimeron/Profiles", directoryHint: .isDirectory)
    }

    public func load() throws -> Snapshot {
        try prepareDirectory()
        var profiles: [(profile: StoredProfile, created: Date)] = []
        var unreadableCount = 0
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
            .filter({ $0.pathExtension == "conf" }) {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { unreadableCount += 1; continue }
            do {
                let doc = try ConfigDocument(data: ConfigDocument.readLimited(url))
                let created = try url.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast
                profiles.append((StoredProfile(id: id, document: doc), created))
            } catch { unreadableCount += 1 }
        }
        let hasSavedOrder = FileManager.default.fileExists(atPath: orderFile.path)
        let order = readOrder()
        var positions: [UUID: Int] = [:]
        for (index, id) in order.enumerated() where positions[id] == nil { positions[id] = index }
        profiles.sort {
            if !hasSavedOrder {
                let names = $0.profile.document.name.localizedStandardCompare($1.profile.document.name)
                return names == .orderedSame
                    ? $0.profile.id.uuidString < $1.profile.id.uuidString
                    : names == .orderedAscending
            }
            let left = positions[$0.profile.id] ?? Int.max
            let right = positions[$1.profile.id] ?? Int.max
            if left != right { return left < right }
            return $0.created == $1.created
                ? $0.profile.id.uuidString < $1.profile.id.uuidString
                : $0.created < $1.created
        }
        return Snapshot(profiles: profiles.map(\.profile), unreadableCount: unreadableCount)
    }

    public func move(_ id: UUID, by offset: Int) throws -> [StoredProfile] {
        let visible = try load().profiles
        guard let index = visible.firstIndex(where: { $0.id == id }),
              visible.indices.contains(index + offset) else { return visible }
        var order = readOrder()
        var known = Set(order)
        for profile in visible {
            if known.insert(profile.id).inserted { order.append(profile.id) }
        }
        let other = visible[index + offset].id
        guard let from = order.firstIndex(of: id), let to = order.firstIndex(of: other) else { return visible }
        order.swapAt(from, to)
        try JSONEncoder().encode(order).write(to: orderFile, options: .atomic)
        return try load().profiles
    }

    private func readOrder() -> [UUID] {
        guard let data = try? Data(contentsOf: orderFile),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else { return [] }
        var seen: Set<UUID> = []
        return ids.filter { seen.insert($0).inserted }
    }

    public func add(_ document: ConfigDocument) throws -> StoredProfile {
        try document.validateLocally()
        let existing = try load().profiles.map(\.id)
        let profile = StoredProfile(document: document)
        try JSONEncoder().encode(existing + [profile.id]).write(to: orderFile, options: .atomic)
        try save(profile, replacing: false)
        return profile
    }

    /// New editor profiles use the same protected staging and precommit checks as updates.
    public func add(_ document: ConfigDocument,
                    validate: @Sendable (URL) async throws -> Void) async throws -> StoredProfile {
        try document.validateLocally()
        try prepareDirectory()
        let profile = StoredProfile(document: document)
        let temporary = try stage(profile)
        defer { unlink(temporary.path) }
        try await validate(temporary)
        guard try ConfigDocument.readLimited(temporary) == Data(document.text.utf8) else {
            throw EditorSaveError.changedStaging
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        try Task.checkCancellation()
        let destination = file(for: profile.id)
        // link is an atomic, exclusive commit: it cannot overwrite an existing profile.
        guard link(temporary.path, destination.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        return profile
    }

    public func update(_ profile: StoredProfile) throws {
        try profile.document.validateLocally()
        guard FileManager.default.fileExists(atPath: file(for: profile.id).path) else { throw ProfileError.missing("Profile") }
        try save(profile, replacing: true)
    }

    /// Editor-only save: validate the exact protected bytes that will be renamed.
    /// Cancellation observed before the atomic rename blocks the write; after this commit point it cannot undo the save.
    public func update(_ profile: StoredProfile, expectedOriginal: Data,
                       validate: @Sendable (URL) async throws -> Void) async throws {
        try profile.document.validateLocally()
        try prepareDirectory()
        let destination = file(for: profile.id)
        let temporary = try stage(profile)
        defer { unlink(temporary.path) }
        let creationDate = try destination.resourceValues(forKeys: [.creationDateKey]).creationDate
        try await validate(temporary)
        // Reject a validator that changed the staged document.
        guard try ConfigDocument.readLimited(temporary) == Data(profile.document.text.utf8) else {
            throw EditorSaveError.changedStaging
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        if let creationDate {
            try FileManager.default.setAttributes([.creationDate: creationDate], ofItemAtPath: temporary.path)
        }
        guard try ConfigDocument.readLimited(destination) == expectedOriginal else {
            throw EditorSaveError.staleOriginal
        }
        try Task.checkCancellation()
        guard rename(temporary.path, destination.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    public func importFile(_ original: URL) throws -> StoredProfile {
        let data = try ConfigDocument.readLimited(original)
        var document = try ConfigDocument(data: data)
        if document.name.isEmpty { document.set("Profile", "Name", original.deletingPathExtension().lastPathComponent) }
        try document.inlineFile(relativeTo: original)
        document.resolveFileReferences(relativeTo: original)
        return try add(document)
    }

    @discardableResult public func delete(_ id: UUID) throws -> Date {
        try prepareDirectory()
        let url = file(for: id)
        let created = try url.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast
        try FileManager.default.removeItem(at: url)
        return created
    }

    public func restore(_ profile: StoredProfile, created: Date? = nil) throws {
        try save(profile, replacing: false, created: created)
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func file(for id: UUID) -> URL { directory.appending(path: id.uuidString + ".conf") }

    private func save(_ profile: StoredProfile, replacing: Bool, created: Date? = nil) throws {
        try prepareDirectory()
        let destination = file(for: profile.id)
        let creationDate = created ?? (replacing ? try? FileManager.default.attributesOfItem(atPath: destination.path)[.creationDate] as? Date : nil)
        let temporary = try stage(profile)
        defer { unlink(temporary.path) }
        if !replacing && FileManager.default.fileExists(atPath: destination.path) { throw ProfileError.duplicate("Profile") }
        if let creationDate {
            try FileManager.default.setAttributes([.creationDate: creationDate], ofItemAtPath: temporary.path)
        }
        guard rename(temporary.path, destination.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    private func stage(_ profile: StoredProfile) throws -> URL {
        let temporary = directory.appending(path: UUID().uuidString + ".tmp")
        let data = Data(profile.document.text.utf8)
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            unlink(temporary.path)
            throw error
        }
        return temporary
    }
}
